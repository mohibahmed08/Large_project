import 'package:flutter/foundation.dart';

class ApiConfig {
  static String get baseUrl {
    const configuredBaseUrl = String.fromEnvironment('API_BASE_URL');
    if (configuredBaseUrl.isNotEmpty) {
      return configuredBaseUrl;
    }

    if (kDebugMode && kIsWeb) {
      return 'http://localhost:5000/api';
    }

    return 'https://calendarplusplus.xyz/api';
  }
}
