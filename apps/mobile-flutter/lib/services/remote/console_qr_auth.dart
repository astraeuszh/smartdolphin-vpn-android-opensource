import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../../features/auth/domain/account_session.dart';
import 'console_auth.dart';
import 'console_endpoint.dart';

class ConsoleQrAuth {
  ConsoleQrAuth({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const String _authBase = 'https://smartdolphinvpn.com';

  static Future<Map<String, dynamic>> _payload({
    required String deviceId,
    Map<String, dynamic>? extra,
  }) async {
    final info = await PackageInfo.fromPlatform();
    return {
      'client': 'android',
      'version': info.version,
      'build': info.buildNumber,
      'device_id': deviceId,
      if (extra != null) ...extra,
    };
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final uri = Uri.parse('$_authBase$path');
    http.Response resp;
    try {
      resp = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 18));
    } on Object {
      throw ConsoleAuthException(
          'E6005', 'Cannot connect to server. Check your network');
    }
    if (resp.statusCode == 404) {
      throw ConsoleAuthException(
        'qr_not_available',
        'QR sign-in is not enabled on the server. Contact an administrator to update the backend',
      );
    }
    if (resp.statusCode >= 500) {
      throw ConsoleAuthException(
          'E6005', 'Server is not responding. Please try again later');
    }
    Map<String, dynamic> data;
    try {
      data = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {
      throw ConsoleAuthException('E6007', 'Invalid server response');
    }
    return data;
  }

  Future<Map<String, dynamic>> createChallenge({
    required String deviceId,
  }) async {
    final body = await _payload(deviceId: deviceId);
    final data = await _post('/api/auth/qr/create', body);
    if (data['ok'] != true) {
      throw ConsoleAuthException(
        (data['code'] as String?) ?? 'qr_failed',
        (data['error'] as String?) ?? 'Unable to create sign-in QR code',
      );
    }
    return data;
  }

  Future<void> approveChallenge({
    required AccountSession session,
    required String challengeId,
  }) async {
    final body = await _payload(
      deviceId: session.deviceId,
      extra: {
        'uid': '${session.uid}',
        'session_token': session.sessionToken,
        'username': session.username,
        'password': session.password,
        'challenge_id': challengeId,
      },
    );
    final data = await _post('/api/auth/qr/approve', body);
    if (data['ok'] != true) {
      throw ConsoleAuthException(
        (data['code'] as String?) ?? 'qr_failed',
        (data['error'] as String?) ?? 'QR authorization failed',
      );
    }
  }

  Future<Map<String, dynamic>> pollChallenge({
    required String deviceId,
    required String challengeId,
  }) async {
    final body = await _payload(
      deviceId: deviceId,
      extra: {'challenge_id': challengeId},
    );
    return _post('/api/auth/qr/poll', body);
  }

  static String? parseChallengeId(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    try {
      final map = jsonDecode(trimmed) as Map<String, dynamic>;
      if (map['t'] == 'login' && map['id'] is String) {
        return map['id'] as String;
      }
    } catch (_) {}
    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.queryParameters['id'] != null) {
      return uri.queryParameters['id'];
    }
    return null;
  }
}
