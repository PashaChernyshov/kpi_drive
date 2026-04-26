import 'package:kpi_drive_app/core/config/app_config.dart';
import 'package:kpi_drive_app/core/network/api_client.dart';
import 'package:kpi_drive_app/features/kanban/domain/kanban_task.dart';

class KanbanApiService {
  KanbanApiService({
    required this.apiClient,
    required this.config,
  });

  final ApiClient apiClient;
  final AppConfig config;

  static const _loadTimeout = Duration(seconds: 20);
  static const _saveTimeout = Duration(seconds: 15);

  static const Map<String, String> _loadFields = {
    'period_start': '2026-04-01',
    'period_end': '2026-04-30',
    'period_key': 'month',
    'requested_mo_id': '42',
    'behaviour_key': 'task,kpi_task',
    'with_result': 'false',
    'response_fields': 'name,indicator_to_mo_id,parent_id,order',
    'auth_user_id': '40',
  };

  static const Map<String, String> _saveBaseFields = {
    'period_start': '2025-09-01',
    'period_end': '2025-09-30',
    'period_key': 'month',
    'auth_user_id': '40',
  };

  static const Map<String, String> _saveFallbackFields = {
    'period_start': '2026-04-01',
    'period_end': '2026-04-30',
    'period_key': 'month',
    'auth_user_id': '40',
  };

  Future<LoadTasksResponse> loadTasks() async {
    try {
      final response = await apiClient.postFormData(
        uri: config.resolve(AppConfig.indicatorsPath),
        fields: _loadFields,
        bearerToken: config.shouldSendBearerToken ? config.token : null,
        timeout: _loadTimeout,
      );

      final rawSnippet = _buildSnippet(response.body, limit: 1000);

      if (!response.isSuccessful) {
        return LoadTasksResponse.error(
          rawSnippet: rawSnippet,
          message: _mapLoadError(response.statusCode, response.body),
        );
      }

      final rows = _extractTaskList(response.decodedBody);
      if (rows == null) {
        return LoadTasksResponse.unknownFormat(rawSnippet: rawSnippet);
      }

      final tasks = rows.map(KanbanTask.fromJson).toList();
      return LoadTasksResponse.success(tasks: tasks, rawSnippet: rawSnippet);
    } on ApiException catch (error) {
      return LoadTasksResponse.error(
        rawSnippet: '',
        message: error.message,
      );
    }
  }

  Future<void> saveTaskField({
    required int taskId,
    required String fieldName,
    required String fieldValue,
  }) async {
    try {
      // The spec uses a different save period than the loaded board. We try the
      // save-example period first and fall back to the actual board period when
      // the backend rejects the request or returns a non-applied ghost-success.
      var response = await _sendSaveRequest(
        taskId: taskId,
        fieldName: fieldName,
        fieldValue: fieldValue,
        baseFields: _saveBaseFields,
      );

      if (_shouldRetrySaveWithLoadPeriod(response, fieldName: fieldName)) {
        response = await _sendSaveRequest(
          taskId: taskId,
          fieldName: fieldName,
          fieldValue: fieldValue,
          baseFields: _saveFallbackFields,
        );
      }

      _ensureSaveSucceeded(response);
    } on ApiException {
      rethrow;
    } catch (error) {
      throw ApiException(error.toString());
    }
  }

  Future<ApiResponse> _sendSaveRequest({
    required int taskId,
    required String fieldName,
    required String fieldValue,
    required Map<String, String> baseFields,
  }) {
    return apiClient.postFormData(
      uri: config.resolve(AppConfig.saveIndicatorFieldPath),
      fields: {
        ...baseFields,
        'indicator_to_mo_id': taskId.toString(),
        'field_name': fieldName,
        'field_value': fieldValue,
      },
      bearerToken: config.shouldSendBearerToken ? config.token : null,
      timeout: _saveTimeout,
    );
  }

  void _ensureSaveSucceeded(ApiResponse response) {
    if (!response.isSuccessful) {
      throw ApiException(_mapSaveError(response.statusCode, response.body));
    }

    final payload = response.decodedBody;
    if (payload is Map<String, dynamic>) {
      final status = payload['STATUS']?.toString().toUpperCase();
      final messages = payload['MESSAGES'];
      final errorMessage = _extractBackendError(messages);
      if (status != 'OK' || errorMessage != null) {
        throw ApiException(errorMessage ?? 'Backend не подтвердил сохранение.');
      }
      return;
    }

    if (payload is Map) {
      final normalized = payload.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      final status = normalized['STATUS']?.toString().toUpperCase();
      if (status == 'OK') {
        return;
      }
    }

    throw const ApiException('Backend вернул неожиданный ответ при сохранении.');
  }

  bool _shouldRetrySaveWithLoadPeriod(
    ApiResponse response, {
    required String fieldName,
  }) {
    if (!response.isSuccessful) {
      return _shouldRetryRejectedSave(response.body, response.statusCode);
    }

    final payload = response.decodedBody;
    if (payload is! Map) {
      return false;
    }

    final normalized = payload.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    final messages = normalized['MESSAGES'];
    final warningText = _extractBackendWarning(messages)?.toLowerCase() ?? '';
    final data = normalized['DATA'];

    final looksLikeGhostSuccess = warningText.contains('не удалось получить данные') &&
        (data == null || (data is Map && data.isEmpty));

    if (looksLikeGhostSuccess) {
      return true;
    }

    // parent_id/order saves normally come back with DATA or with a stable OK
    // body from the actual board period. If the save-example period returns OK
    // but no data and a generic warning, prefer retrying on the loaded period.
    if ((fieldName == 'parent_id' || fieldName == 'order') &&
        warningText.isNotEmpty &&
        warningText.contains('показател')) {
      return true;
    }

    return false;
  }

  bool _shouldRetryRejectedSave(String body, int statusCode) {
    if (!(statusCode == 400 ||
        statusCode == 401 ||
        statusCode == 403 ||
        statusCode == 422)) {
      return false;
    }

    final lower = body.toLowerCase();
    return lower.contains('закрытом периоде') ||
        lower.contains('closed period') ||
        lower.contains('period') ||
        lower.contains('невозможно сохранить') ||
        lower.contains('cannot save') ||
        lower.contains('не найден') ||
        lower.contains('not found') ||
        lower.contains('indicator');
  }

  List<Map<String, dynamic>>? _extractTaskList(dynamic payload) {
    final list = _findList(payload);
    if (list == null) {
      return null;
    }

    return list
        .whereType<Map>()
        .map(
          (item) => item.map(
            (key, value) => MapEntry(key.toString(), value),
          ),
        )
        .toList();
  }

  List<dynamic>? _findList(dynamic value) {
    if (value is List) {
      return value;
    }

    if (value is Map) {
      final checks = [
        value,
        value['data'],
        value['DATA'],
        value['data'] is Map ? value['data']['items'] : null,
        value['DATA'] is Map ? value['DATA']['items'] : null,
        value['indicators'],
        value['data'] is Map ? value['data']['indicators'] : null,
        value['DATA'] is Map ? value['DATA']['indicators'] : null,
        value['rows'],
        value['data'] is Map ? value['data']['rows'] : null,
        value['DATA'] is Map ? value['DATA']['rows'] : null,
      ];

      for (final candidate in checks) {
        if (candidate is List) {
          return candidate;
        }
      }
    }

    return null;
  }

  String _mapLoadError(int statusCode, String body) {
    if (statusCode == 401 || statusCode == 403) {
      return 'Ошибка авторизации. Проверьте bearer token.';
    }

    if (config.usesLocalProxy &&
        (statusCode == 500 ||
            statusCode == 502 ||
            statusCode == 503 ||
            statusCode == 504)) {
      return 'API KPI-DRIVE временно недоступен или proxy не смог выполнить запрос.';
    }

    return 'Ошибка загрузки данных KPI-DRIVE ($statusCode). ${_buildSnippet(body)}';
  }

  String _mapSaveError(int statusCode, String body) {
    if (statusCode == 401 || statusCode == 403) {
      if (_looksLikeBackendValidation(body)) {
        return 'Backend отклонил сохранение. Проверьте поля parent_id/order.';
      }
      return 'Ошибка авторизации. Проверьте bearer token.';
    }

    if (statusCode == 400 || statusCode == 422) {
      return 'Backend отклонил сохранение. Проверьте поля parent_id/order.';
    }

    if (statusCode == 404) {
      return 'Endpoint сохранения не найден или задача недоступна.';
    }

    if (config.usesLocalProxy &&
        (statusCode == 500 ||
            statusCode == 502 ||
            statusCode == 503 ||
            statusCode == 504)) {
      return 'API KPI-DRIVE временно недоступен.';
    }

    return 'Не удалось сохранить изменения ($statusCode). ${_buildSnippet(body)}';
  }

  String? _extractBackendError(dynamic messages) {
    if (messages is! Map) {
      return null;
    }

    final error = messages['error'];
    if (error == null) {
      return null;
    }

    if (error is List && error.isNotEmpty) {
      return error.join(' ');
    }

    final text = error.toString().trim();
    if (text.isEmpty || text == 'null') {
      return null;
    }
    return text;
  }

  String? _extractBackendWarning(dynamic messages) {
    if (messages is! Map) {
      return null;
    }

    final warning = messages['warning'];
    if (warning == null) {
      return null;
    }

    if (warning is List && warning.isNotEmpty) {
      return warning.join(' ');
    }

    final text = warning.toString().trim();
    if (text.isEmpty || text == 'null') {
      return null;
    }
    return text;
  }

  bool _looksLikeBackendValidation(String body) {
    final lower = body.toLowerCase();
    return lower.contains('закрытом периоде') ||
        lower.contains('field') ||
        lower.contains('parent_id') ||
        lower.contains('order') ||
        lower.contains('period') ||
        lower.contains('сохран');
  }

  String _buildSnippet(String body, {int limit = 300}) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    return trimmed.length <= limit ? trimmed : '${trimmed.substring(0, limit)}...';
  }
}

class LoadTasksResponse {
  const LoadTasksResponse.success({
    required this.tasks,
    required this.rawSnippet,
  })  : mode = LoadTasksMode.success,
        message = null;

  const LoadTasksResponse.error({
    required this.message,
    required this.rawSnippet,
  })  : mode = LoadTasksMode.error,
        tasks = const [];

  const LoadTasksResponse.unknownFormat({
    required this.rawSnippet,
  })  : mode = LoadTasksMode.unknownFormat,
        tasks = const [],
        message = 'KPI-DRIVE вернул успешный ответ, но формат данных не распознан.';

  final LoadTasksMode mode;
  final List<KanbanTask> tasks;
  final String? message;
  final String rawSnippet;
}

enum LoadTasksMode {
  success,
  error,
  unknownFormat,
}
