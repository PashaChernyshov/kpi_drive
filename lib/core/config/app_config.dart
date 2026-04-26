import 'package:flutter/foundation.dart';

class AppConfig {
  AppConfig._();

  static final AppConfig instance = AppConfig._();

  static const String directApiBaseUrl = 'https://api.dev.kpi-drive.ru';
  static const String defaultWebProxyBaseUrl = 'http://127.0.0.1:8787';
  static const String indicatorsPath = '/_api/indicators/get_mo_indicators';
  static const String saveIndicatorFieldPath =
      '/_api/indicators/save_indicator_instance_field';
  static const String appTitle = 'KPI-DRIVE';

  String get apiBaseUrl {
    const configuredBaseUrl =
        String.fromEnvironment('KPI_DRIVE_API_BASE_URL');
    if (configuredBaseUrl.isNotEmpty) {
      return configuredBaseUrl;
    }
    if (kIsWeb) {
      return defaultWebProxyBaseUrl;
    }
    return directApiBaseUrl;
  }

  String get token => const String.fromEnvironment('KPI_DRIVE_TOKEN');

  bool get hasToken => token.trim().isNotEmpty;

  bool get usesLocalProxy {
    final uri = Uri.tryParse(apiBaseUrl);
    if (uri == null) {
      return false;
    }
    return uri.host == '127.0.0.1' || uri.host == 'localhost';
  }

  bool get shouldSendBearerToken => !usesLocalProxy;

  Uri resolve(String path) => Uri.parse('$apiBaseUrl$path');
}
