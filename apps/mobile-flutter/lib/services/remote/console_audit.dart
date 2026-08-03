import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../../features/auth/domain/account_session.dart';
import 'console_endpoint.dart';
import 'client_request_headers.dart';

class ConsoleAudit {
  ConsoleAudit({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<String> policy(AccountSession session) async {
    final response = await _client
        .get(
          Uri.parse('${ConsoleEndpoint.base}/api/auth/audit-policy'),
          headers: await ClientRequestHeaders.standard(
            bearerToken: session.sessionToken,
          ),
        )
        .timeout(const Duration(seconds: 12));
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400 || body['ok'] != true) {
      throw Exception('audit policy unavailable');
    }
    return (body['mode'] as String?) ?? 'basic';
  }

  Future<String> updatePolicy(AccountSession session, String mode) async {
    final response = await _client
        .patch(
          Uri.parse('${ConsoleEndpoint.base}/api/auth/audit-policy'),
          headers: await ClientRequestHeaders.standard(
            bearerToken: session.sessionToken,
            json: true,
          ),
          body: jsonEncode({
            'mode': mode,
            'consent': mode != 'basic',
          }),
        )
        .timeout(const Duration(seconds: 12));
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400 || body['ok'] != true) {
      throw Exception('audit policy update failed');
    }
    return (body['mode'] as String?) ?? mode;
  }

  Future<void> report(
    AccountSession session, {
    required String event,
    Map<String, dynamic> metadata = const {},
  }) async {
    if (session.sessionToken.trim().isEmpty) return;
    final info = await PackageInfo.fromPlatform();
    final response = await _client
        .post(
          Uri.parse('${ConsoleEndpoint.base}/api/client/audit-events'),
          headers: await ClientRequestHeaders.standard(
            bearerToken: session.sessionToken,
            json: true,
          ),
          body: jsonEncode({
            'event': event,
            'metadata': {
              ...metadata,
              'app_version': info.version,
              'build': info.buildNumber,
            },
          }),
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode >= 400) {
      throw Exception('audit report failed: ${response.statusCode}');
    }
  }
}
