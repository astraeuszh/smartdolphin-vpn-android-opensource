import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../../features/auth/domain/account_session.dart';
import 'console_endpoint.dart';

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
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 18));
    Map<String, dynamic> data;
    try {
      data = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {
      throw ConsoleAuthException('E6007', '服务器响应无效');
    }
    return data;
  }

  void _throwIfFailed(Map<String, dynamic> data) {
    if (data['ok'] == true) return;
    final code = (data['code'] as String?) ?? 'auth_failed';
    final msg = (data['error'] as String?) ??
        (data['message'] as String?) ??
        '认证失败';
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
        'username': username.trim(),
        'password': password,
      },
    );
    final data = await _post('/api/client/login', body);
    if (data['ok'] != true) {
      if (data['code'] == 'pending' && data['uid'] != null) {
        return AccountSession.fromJson(
          username: username.trim(),
          password: password,
          deviceId: deviceId,
          data: data,
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
    final body = await _clientPayload(
      deviceId: deviceId,
      extra: {'email': email.trim().toLowerCase()},
    );
    final data = await _post('/api/client/register/send-code', body);
    _throwIfFailed(data);
  }

  Future<AccountSession> register({
    required String username,
    required String password,
    required String email,
    required String verificationCode,
    required String deviceId,
  }) async {
    final body = await _clientPayload(
      deviceId: deviceId,
      extra: {
        'username': username.trim(),
        'password': password,
        'email': email.trim().toLowerCase(),
        'verification_code': verificationCode.trim(),
      },
    );
    final data = await _post('/api/client/register', body);
    _throwIfFailed(data);
    return AccountSession.fromJson(
      username: username.trim(),
      password: password,
      deviceId: deviceId,
      data: data,
    );
  }

  Future<AccountSession> checkSession(AccountSession session) async {
    final body = await _clientPayload(
      deviceId: session.deviceId,
      extra: {
        'uid': session.uid,
        'session_token': session.sessionToken,
        'username': session.username,
        'password': session.password,
      },
    );
    final data = await _post('/api/client/check', body);
    if (data['banned'] == true || data['code'] == 'banned') {
      throw ConsoleAuthException(
        'banned',
        (data['message'] as String?) ??
            (data['ban_reason'] as String?) ??
            '账户已封禁',
      );
    }
    _throwIfFailed(data);
    return session.copyWithRemote(data);
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
    return ConsoleAuthException('E6005', '无法连接控制台，请检查网络');
  }
}
