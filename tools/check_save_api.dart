import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

Future<void> main(List<String> arguments) async {
  final params = _parseArgs(arguments);
  final indicatorId = params['indicator-to-mo-id'];
  final parentId = params['parent-id'];
  final order = params['order'];

  if (indicatorId == null || parentId == null || order == null) {
    stderr.writeln(
      'Usage: dart run tools/check_save_api.dart --indicator-to-mo-id <id> --parent-id <parentId> --order <order>',
    );
    exitCode = 64;
    return;
  }

  final token = _readTokenFromEnvLocal();
  if (token == null || token.isEmpty) {
    stderr.writeln('.env.local not found or KPI_DRIVE_TOKEN is empty.');
    exitCode = 64;
    return;
  }

  await _runSave(
    token: token,
    indicatorId: indicatorId,
    fieldName: 'parent_id',
    fieldValue: parentId,
  );

  await _runSave(
    token: token,
    indicatorId: indicatorId,
    fieldName: 'order',
    fieldValue: order,
  );
}

Future<void> _runSave({
  required String token,
  required String indicatorId,
  required String fieldName,
  required String fieldValue,
}) async {
  final periods = [
    const _SavePeriod('2025-09-01', '2025-09-30', 'month'),
    const _SavePeriod('2026-04-01', '2026-04-30', 'month'),
  ];

  for (var index = 0; index < periods.length; index++) {
    final period = periods[index];
    final request = http.MultipartRequest(
      'POST',
      Uri.parse(
        'https://api.dev.kpi-drive.ru/_api/indicators/save_indicator_instance_field',
      ),
    )
      ..headers['Authorization'] = 'Bearer $token'
      ..fields.addAll({
        'period_start': period.start,
        'period_end': period.end,
        'period_key': period.key,
        'indicator_to_mo_id': indicatorId,
        'auth_user_id': '40',
        'field_name': fieldName,
        'field_value': fieldValue,
      });

    final response = await http.Response.fromStream(await request.send());
    final body = utf8.decode(response.bodyBytes, allowMalformed: true);
    final snippet = body.length <= 1000 ? body : '${body.substring(0, 1000)}...';

    stdout.writeln(
      'field=$fieldName period=${period.start}..${period.end} status=${response.statusCode}',
    );
    stdout.writeln(snippet);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }

    if (!_shouldRetry(body, response.statusCode) || index == periods.length - 1) {
      return;
    }
  }
}

bool _shouldRetry(String body, int statusCode) {
  if (!(statusCode == 400 || statusCode == 401 || statusCode == 403 || statusCode == 422)) {
    return false;
  }
  final lower = body.toLowerCase();
  return lower.contains('закрытом периоде') ||
      lower.contains('period') ||
      lower.contains('cannot save') ||
      lower.contains('невозможно');
}

Map<String, String> _parseArgs(List<String> args) {
  final result = <String, String>{};
  for (var i = 0; i < args.length - 1; i++) {
    final arg = args[i];
    if (arg.startsWith('--')) {
      result[arg.substring(2)] = args[i + 1];
      i++;
    }
  }
  return result;
}

String? _readTokenFromEnvLocal() {
  final file = File('.env.local');
  if (!file.existsSync()) {
    return null;
  }

  for (final line in file.readAsLinesSync()) {
    final trimmed = line.trim();
    if (trimmed.startsWith('KPI_DRIVE_TOKEN=')) {
      return trimmed.substring('KPI_DRIVE_TOKEN='.length).trim();
    }
  }
  return null;
}

class _SavePeriod {
  const _SavePeriod(this.start, this.end, this.key);

  final String start;
  final String end;
  final String key;
}
