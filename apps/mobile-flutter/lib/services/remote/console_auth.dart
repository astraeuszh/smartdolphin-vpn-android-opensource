import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../../features/auth/domain/account_session.dart';
import 'console_endpoint.dart';
import 'client_request_headers.dart';

class ConsoleAuthException implements Exception {
  ConsoleAuthException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}

class ConsoleAuth {
  ConsoleAuth({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static Future<Map<String, dynamic>> _clientPayload({
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
    final uri = Uri.parse('${ConsoleEndpoint.base}$path');
    final resp = await _client
        .post(
          uri,
          headers: await ClientRequestHeaders.standard(json: true),
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 18));
    Map<String, dynamic> data;
    try {
      data = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {
      throw ConsoleAuthException('E6007', 'Invalid server response');
    }
    _throwForHttpStatus(resp.statusCode, data);
    return data;
  }

  Future<Map<String, dynamic>> _getWithToken(
    String path,
    String token,
  ) async {
    final uri = Uri.parse('${ConsoleEndpoint.base}$path');
    final resp = await _client
        .get(
          uri,
          headers: await ClientRequestHeaders.standard(bearerToken: token),
        )
        .timeout(const Duration(seconds: 18));
    Map<String, dynamic> data;
    try {
      data = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {
      throw ConsoleAuthException('E6007', 'Invalid server response');
    }
    _throwForHttpStatus(resp.statusCode, data);
    return data;
  }

  void _throwForHttpStatus(int statusCode, [Map<String, dynamic>? body]) {
    if (statusCode == 401 || statusCode == 403) {
      final error = body?['error']?.toString() ?? '';
      if (error == 'account_deleted') {
        throw ConsoleAuthException(
            'account_deleted', 'This account has been deleted.');
      }
      if (error == 'account_expired') {
        throw ConsoleAuthException(
            'account_expired', 'Subscription has expired.');
      }
      if (error == 'account_suspended_notice') {
        throw ConsoleAuthException('banned', 'Account access is restricted.');
      }
      throw ConsoleAuthException(
          'unauthorized', 'Authentication expired. Please sign in again.');
    }
    if (statusCode >= 500) {
      throw ConsoleAuthException(
          'server_unavailable', 'Server is temporarily unavailable');
    }
  }

  void _throwIfFailed(Map<String, dynamic> data) {
    if (data['ok'] == true) return;
    final code = (data['code'] as String?) ?? 'auth_failed';
    var msg = (data['error'] as String?) ??
        (data['message'] as String?) ??
        'Authentication failed';
    if (msg.contains('device registration limit reached')) {
      if (msg.contains('per day')) {
        msg =
            "This device has reached today's registration limit (up to 3 accounts per day)";
      } else if (msg.contains('per year')) {
        msg =
            "This device has reached this year's registration limit (up to 3 accounts per year)";
      } else {
        msg = 'This device has reached the registration limit';
      }
    } else if (msg.contains('hardware device id required') ||
        msg.contains('invalid hardware device id')) {
      msg =
          'Device hardware identifier cannot be recognized. Please update the client and try again';
    }
    throw ConsoleAuthException(code, msg);
  }

  Future<AccountSession> login({
    required String username,
    required String password,
    required String deviceId,
  }) async {
    final body = await _clientPayload(
      deviceId: deviceId,
      extra: {
        'identifier': username.trim(),
        'password': password,
      },
    );
    final data = await _post('/api/auth/login', body);
    if (data['ok'] != true) {
      if (data['code'] == 'pending' && data['uid'] != null) {
        return AccountSession.fromJson(
          username: username.trim(),
          password: password,
          deviceId: deviceId,
          data: data,
        );
      }
      if (data['banned'] == true || data['code'] == 'banned') {
        return AccountSession.fromJson(
          username: username.trim(),
          password: password,
          deviceId: deviceId,
          data: {
            ...data,
            'banned': true,
          },
        );
      }
      _throwIfFailed(data);
    }
    return AccountSession.fromJson(
      username: username.trim(),
      password: password,
      deviceId: deviceId,
      data: data,
    );
  }

  Future<void> sendRegisterCode({
    required String email,
    required String deviceId,
  }) async {
    return;
  }

  Future<AccountSession> register({
    required String username,
    required String password,
    required String email,
    required String verificationCode,
    required String deviceId,
    required String hardwareDeviceId,
  }) async {
    final body = await _clientPayload(
      deviceId: deviceId,
      extra: {
        'username': username.trim(),
        'displayName': username.trim(),
        'password': password,
        'email': email.trim().toLowerCase(),
        'verification_code': verificationCode.trim(),
        'hardware_device_id': hardwareDeviceId,
      },
    );
    final data = await _post('/api/auth/register', body);
    _throwIfFailed(data);
    return AccountSession.fromJson(
      username: username.trim(),
      password: password,
      deviceId: deviceId,
      data: data,
    );
  }

  Future<AccountSession> checkSession(AccountSession session) async {
    final data =
        await _getWithToken('/api/auth/account-status', session.sessionToken);
    if (data['banned'] == true || data['code'] == 'banned') {
      return AccountSession.fromJson(
        username: session.username,
        password: session.password,
        deviceId: session.deviceId,
        data: {
          ...data,
          'session_token': session.sessionToken,
          'banned': true,
        },
      );
    }
    _throwIfFailed(data);
    return session.copyWithRemote(data);
  }

  Future<void> setPresence(AccountSession session, bool online) async {
    final response = await _client
        .post(
          Uri.parse('${ConsoleEndpoint.base}/api/auth/presence'),
          headers: await ClientRequestHeaders.standard(
            bearerToken: session.sessionToken,
            json: true,
          ),
          body: jsonEncode({'online': online}),
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw ConsoleAuthException(
          'unauthorized', 'Authentication expired. Please sign in again.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ConsoleAuthException('presence_failed', 'Presence update failed.');
    }
  }

  Future<String> renameUser({
    required AccountSession session,
    required String newUsername,
    required String password,
  }) async {
    final body = await _clientPayload(
      deviceId: session.deviceId,
      extra: {
        'uid': session.uid,
        'username': session.username,
        'password': password,
        'new_username': newUsername.trim(),
      },
    );
    final data = await _post('/api/client/account/rename', body);
    _throwIfFailed(data);
    return (data['username'] as String?)?.trim() ?? newUsername.trim();
  }

  Future<String> changeEmail({
    required AccountSession session,
    required String currentEmail,
    required String newEmail,
    required String password,
  }) async {
    final body = await _clientPayload(
      deviceId: session.deviceId,
      extra: {
        'uid': session.uid,
        'username': session.username,
        'password': password,
        'current_email': currentEmail.trim().toLowerCase(),
        'new_email': newEmail.trim().toLowerCase(),
      },
    );
    final data = await _post('/api/client/account/email', body);
    _throwIfFailed(data);
    return (data['email'] as String?)?.trim() ?? newEmail.trim().toLowerCase();
  }

  Future<void> changePassword({
    required AccountSession session,
    required String oldPassword,
    required String newPassword,
  }) async {
    final body = await _clientPayload(
      deviceId: session.deviceId,
      extra: {
        'uid': session.uid,
        'username': session.username,
        'old_password': oldPassword,
        'new_password': newPassword,
      },
    );
    final data = await _post('/api/client/account/password', body);
    _throwIfFailed(data);
  }

  Future<void> resetPasswordWithCode({
    required AccountSession session,
    required String email,
    required String verificationCode,
    required String newPassword,
  }) async {
    final body = await _clientPayload(
      deviceId: session.deviceId,
      extra: {
        'uid': session.uid,
        'username': session.username,
        'email': email.trim().toLowerCase(),
        'verification_code': verificationCode.trim(),
        'new_password': newPassword,
      },
    );
    final data = await _post('/api/client/account/password/reset', body);
    _throwIfFailed(data);
  }

  Future<void> sendPasswordChangeCode({
    required String email,
    required String deviceId,
  }) async {
    final body = await _clientPayload(
      deviceId: deviceId,
      extra: {'email': email.trim().toLowerCase()},
    );
    final data = await _post('/api/client/register/send-code', body);
    _throwIfFailed(data);
  }

  static ConsoleAuthException mapNetwork(Object e) {
    debugPrint('[ConsoleAuth] network error: $e');
    return ConsoleAuthException(
        'E6005', 'Cannot connect to console. Check your network');
  }
}
