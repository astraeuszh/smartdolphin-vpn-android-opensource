import 'package:package_info_plus/package_info_plus.dart';

/// Identifies application requests at the API boundary. The server uses the
/// numeric build for the forced-update gate before serving authenticated data.
class ClientRequestHeaders {
  static Future<Map<String, String>> standard({
    String? bearerToken,
    bool json = false,
  }) async {
    final info = await PackageInfo.fromPlatform();
    return {
      'X-SmartDolphin-Client': 'android',
      'X-SmartDolphin-Version': info.version,
      'X-SmartDolphin-Build': info.buildNumber,
      if (bearerToken != null && bearerToken.isNotEmpty)
        'Authorization': 'Bearer $bearerToken',
      if (json) 'Content-Type': 'application/json',
    };
  }
}
