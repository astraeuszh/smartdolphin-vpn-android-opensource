import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../../features/auth/domain/account_session.dart';
import 'console_endpoint.dart';

class ConsoleTraffic {
  ConsoleTraffic({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<void> reportBytes({
    required AccountSession session,
    required int bytes,
  }) async {
    if (bytes <= 0) return;
    final info = await PackageInfo.fromPlatform();
    final body = {
      'uid': session.uid,
      'session_token': session.sessionToken,
      'username': session.username,
      'password': session.password,
      'bytes': bytes,
      'client': 'android',
      'version': info.version,
      'build': info.buildNumber,
      'device_id': session.deviceId,
    };
    final uri = Uri.parse('${ConsoleEndpoint.base}/api/client/traffic/report');
    final resp = await _client
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 12));
    if (resp.statusCode >= 400) {
      throw Exception('traffic report failed: ${resp.statusCode}');
    }
  }
}
