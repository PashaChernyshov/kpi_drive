import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

Future<void> main() async {
  final token = _readTokenFromEnvLocal();
  if (token == null || token.isEmpty) {
    stderr.writeln(
      '.env.local не найден или KPI_DRIVE_TOKEN пуст. Создайте .env.local по примеру .env.example.',
    );
    exitCode = 64;
    return;
  }

  final request = http.MultipartRequest(
    'POST',
    Uri.parse('https://api.dev.kpi-drive.ru/_api/indicators/get_mo_indicators'),
  )
    ..headers['Authorization'] = 'Bearer $token'
    ..fields.addAll(const {
      'period_start': '2026-04-01',
      'period_end': '2026-04-30',
      'period_key': 'month',
      'requested_mo_id': '42',
      'behaviour_key': 'task,kpi_task',
      'with_result': 'false',
      'response_fields': 'name,indicator_to_mo_id,parent_id,order',
      'auth_user_id': '40',
    });

  final response = await http.Response.fromStream(await request.send());
  stdout.writeln('Status code: ${response.statusCode}');

  final content = utf8.decode(response.bodyBytes, allowMalformed: true);
  stdout.writeln(
    content.length <= 1500 ? content : '${content.substring(0, 1500)}...',
  );
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
