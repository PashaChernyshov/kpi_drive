import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _defaultHost = '127.0.0.1';
const _defaultPort = 8787;
const _upstreamBaseUrl = 'https://api.dev.kpi-drive.ru';
const _outboundTimeout = Duration(seconds: 20);
const _allowedPaths = {
  '/_api/indicators/get_mo_indicators',
  '/_api/indicators/save_indicator_instance_field',
};

Future<void> main(List<String> arguments) async {
  final config = _ProxyConfig.fromArguments(arguments);
  final token = (config.token ?? Platform.environment['KPI_DRIVE_TOKEN'])?.trim();

  if (token == null || token.isEmpty) {
    stderr.writeln(
      'KPI_DRIVE_TOKEN не передан. Используйте переменную окружения KPI_DRIVE_TOKEN или аргумент --token.',
    );
    exitCode = 64;
    return;
  }

  final server = await HttpServer.bind(config.host, config.port);
  stdout.writeln(
    'KPI-DRIVE dev proxy слушает http://${config.host}:${config.port} token=${_maskToken(token)}',
  );

  ProcessSignal.sigint.watch().listen((_) async {
    stdout.writeln('Остановка dev proxy...');
    await server.close(force: true);
    exit(0);
  });

  await for (final request in server) {
    unawaited(_handleRequest(request, token));
  }
}

Future<void> _handleRequest(HttpRequest request, String token) async {
  _applyCors(request.response);

  if (request.method == 'OPTIONS') {
    request.response.statusCode = HttpStatus.noContent;
    await request.response.close();
    return;
  }

  if (!_allowedPaths.contains(request.uri.path)) {
    await _writeJson(
      request.response,
      HttpStatus.notFound,
      {
        'error': 'Unsupported path',
        'path': request.uri.path,
      },
    );
    return;
  }

  if (request.method != 'POST') {
    await _writeJson(
      request.response,
      HttpStatus.methodNotAllowed,
      {
        'error': 'Method not allowed',
        'method': request.method,
      },
    );
    return;
  }

  final stopwatch = Stopwatch()..start();
  final requestBytes = await request.fold<List<int>>(
    <int>[],
    (buffer, data) => buffer..addAll(data),
  );
  final requestFields = _extractMultipartFields(requestBytes);
  final upstreamClient = HttpClient();

  try {
    final upstreamUri = Uri.parse('$_upstreamBaseUrl${request.uri.path}');
    final upstreamRequest = await upstreamClient.postUrl(upstreamUri).timeout(_outboundTimeout);
    upstreamRequest.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');

    final incomingContentType = request.headers.value(HttpHeaders.contentTypeHeader);
    if (incomingContentType != null && incomingContentType.isNotEmpty) {
      upstreamRequest.headers.set(HttpHeaders.contentTypeHeader, incomingContentType);
    }

    upstreamRequest.add(requestBytes);
    final upstreamResponse = await upstreamRequest.close().timeout(_outboundTimeout);
    final responseBytes = await upstreamResponse.fold<List<int>>(
      <int>[],
      (buffer, data) => buffer..addAll(data),
    ).timeout(_outboundTimeout);

    request.response.statusCode = upstreamResponse.statusCode;

    final responseContentType = upstreamResponse.headers.value(HttpHeaders.contentTypeHeader);
    if (responseContentType != null && responseContentType.isNotEmpty) {
      request.response.headers.set(HttpHeaders.contentTypeHeader, responseContentType);
    } else {
      request.response.headers.contentType = ContentType.json;
    }

    final snippet = utf8.decode(responseBytes, allowMalformed: true);
    final normalizedSnippet =
        snippet.length <= 1000 ? snippet : '${snippet.substring(0, 1000)}...';

    if (request.uri.path == '/_api/indicators/save_indicator_instance_field') {
      stdout.writeln(
        '[proxy] save endpoint=${request.uri.path} status=${upstreamResponse.statusCode} '
        'duration=${stopwatch.elapsedMilliseconds}ms auth=Bearer attached '
        'token=${_maskToken(token)} fields=${_formatSaveFields(requestFields)} body=$normalizedSnippet',
      );
    } else {
      stdout.writeln(
        '[proxy] ${request.method} ${request.uri.path} -> ${upstreamResponse.statusCode} '
        'duration=${stopwatch.elapsedMilliseconds}ms | $normalizedSnippet',
      );
    }

    request.response.add(responseBytes);
    await request.response.close();
  } on TimeoutException catch (error) {
    await _writeProxyFailure(
      request.response,
      request.uri.path,
      HttpStatus.gatewayTimeout,
      'Превышено время ожидания ответа API KPI-DRIVE.',
      error.toString(),
      requestFields: requestFields,
      token: token,
      durationMs: stopwatch.elapsedMilliseconds,
    );
  } on SocketException catch (error) {
    await _writeProxyFailure(
      request.response,
      request.uri.path,
      HttpStatus.badGateway,
      'Не удалось подключиться к API KPI-DRIVE.',
      error.toString(),
      requestFields: requestFields,
      token: token,
      durationMs: stopwatch.elapsedMilliseconds,
    );
  } on HandshakeException catch (error) {
    await _writeProxyFailure(
      request.response,
      request.uri.path,
      HttpStatus.badGateway,
      'TLS-ошибка при подключении к API KPI-DRIVE.',
      error.toString(),
      requestFields: requestFields,
      token: token,
      durationMs: stopwatch.elapsedMilliseconds,
    );
  } catch (error) {
    await _writeProxyFailure(
      request.response,
      request.uri.path,
      HttpStatus.badGateway,
      'Proxy не смог выполнить запрос к API KPI-DRIVE.',
      error.toString(),
      requestFields: requestFields,
      token: token,
      durationMs: stopwatch.elapsedMilliseconds,
    );
  } finally {
    upstreamClient.close(force: true);
  }
}

Map<String, String> _extractMultipartFields(List<int> requestBytes) {
  final text = utf8.decode(requestBytes, allowMalformed: true);
  final matches = RegExp(
    r'name="([^"]+)"\r?\n\r?\n([\s\S]*?)(?=\r?\n--)',
    multiLine: true,
  ).allMatches(text);

  final result = <String, String>{};
  for (final match in matches) {
    final key = match.group(1)?.trim();
    final value = match.group(2)?.trim();
    if (key == null || key.isEmpty || value == null) {
      continue;
    }
    result[key] = value;
  }
  return result;
}

String _formatSaveFields(Map<String, String> fields) {
  const keys = [
    'period_start',
    'period_end',
    'period_key',
    'indicator_to_mo_id',
    'field_name',
    'field_value',
    'auth_user_id',
  ];

  return keys.map((key) => '$key=${fields[key] ?? ''}').join(', ');
}

String _maskToken(String token) {
  if (token.length <= 8) {
    return '***';
  }
  return '${token.substring(0, 4)}***${token.substring(token.length - 4)}';
}

void _applyCors(HttpResponse response) {
  response.headers
    ..set('Access-Control-Allow-Origin', '*')
    ..set('Access-Control-Allow-Headers', '*')
    ..set('Access-Control-Allow-Methods', 'GET,POST,OPTIONS');
}

Future<void> _writeJson(
  HttpResponse response,
  int statusCode,
  Map<String, Object?> body,
) async {
  response.statusCode = statusCode;
  response.headers.contentType = ContentType.json;
  response.write(jsonEncode(body));
  await response.close();
}

Future<void> _writeProxyFailure(
  HttpResponse response,
  String path,
  int statusCode,
  String message,
  String details, {
  required Map<String, String> requestFields,
  required String token,
  required int durationMs,
}) async {
  final snippet = details.length <= 1000 ? details : '${details.substring(0, 1000)}...';

  if (path == '/_api/indicators/save_indicator_instance_field') {
    stdout.writeln(
      '[proxy] save endpoint=$path status=$statusCode duration=${durationMs}ms '
      'auth=Bearer attached token=${_maskToken(token)} '
      'fields=${_formatSaveFields(requestFields)} body=$snippet',
    );
  } else {
    stdout.writeln(
      '[proxy] POST $path -> $statusCode duration=${durationMs}ms | $snippet',
    );
  }

  await _writeJson(
    response,
    statusCode,
    {
      'error': message,
      'details': details,
    },
  );
}

class _ProxyConfig {
  const _ProxyConfig({
    required this.host,
    required this.port,
    required this.token,
  });

  final String host;
  final int port;
  final String? token;

  factory _ProxyConfig.fromArguments(List<String> arguments) {
    String host = _defaultHost;
    int port = _defaultPort;
    String? token;

    for (var index = 0; index < arguments.length; index++) {
      final argument = arguments[index];
      if (argument == '--host' && index + 1 < arguments.length) {
        host = arguments[++index];
        continue;
      }
      if (argument == '--port' && index + 1 < arguments.length) {
        port = int.tryParse(arguments[++index]) ?? _defaultPort;
        continue;
      }
      if (argument == '--token' && index + 1 < arguments.length) {
        token = arguments[++index];
      }
    }

    return _ProxyConfig(host: host, port: port, token: token);
  }
}
