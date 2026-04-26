import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiClient {
  ApiClient({http.Client? httpClient}) : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  Future<ApiResponse> postFormData({
    required Uri uri,
    required Map<String, String> fields,
    String? bearerToken,
    Duration? timeout,
  }) async {
    final isLocalProxy = uri.host == '127.0.0.1' || uri.host == 'localhost';

    try {
      final request = http.MultipartRequest('POST', uri)..fields.addAll(fields);

      final normalizedToken = bearerToken?.trim() ?? '';
      if (normalizedToken.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $normalizedToken';
      }

      final streamedResponse = await _httpClient
          .send(request)
          .timeout(timeout ?? const Duration(seconds: 20));
      final response = await http.Response.fromStream(streamedResponse);

      return ApiResponse(
        statusCode: response.statusCode,
        body: response.body,
        decodedBody: _tryDecodeJson(response.body),
      );
    } on TimeoutException {
      throw const ApiException(
        'Превышено время ожидания ответа API KPI-DRIVE.',
      );
    } on http.ClientException catch (error) {
      if (isLocalProxy) {
        throw const ApiException(
          'Локальный proxy не запущен. Запустите .\\scripts\\run_web_dev.ps1',
        );
      }
      throw ApiException.network(error.message);
    } catch (error) {
      if (isLocalProxy &&
          (error.toString().contains('XMLHttpRequest error') ||
              error.toString().contains('Failed to fetch') ||
              error.toString().contains('Connection refused'))) {
        throw const ApiException(
          'Локальный proxy не запущен. Запустите .\\scripts\\run_web_dev.ps1',
        );
      }
      if (kIsWeb && !isLocalProxy) {
        throw ApiException.network(error.toString());
      }
      throw ApiException.network(error.toString());
    }
  }

  dynamic _tryDecodeJson(String body) {
    if (body.trim().isEmpty) {
      return null;
    }

    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    _httpClient.close();
  }
}

class ApiResponse {
  const ApiResponse({
    required this.statusCode,
    required this.body,
    required this.decodedBody,
  });

  final int statusCode;
  final String body;
  final dynamic decodedBody;

  bool get isSuccessful => statusCode >= 200 && statusCode < 300;
}

class ApiException implements Exception {
  const ApiException(this.message);

  factory ApiException.network(String details) =>
      ApiException('Сетевая ошибка: $details');

  final String message;

  @override
  String toString() => message;
}
