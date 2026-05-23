import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../services/remote/console_auth.dart';
import '../domain/account_session.dart';

const _storageKey = 'smartdolphin_auth_v2';
const _deviceKey = 'smartdolphin_device_id';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository();
});

class AuthRepository {
  AuthRepository({
    FlutterSecureStorage? storage,
    ConsoleAuth? api,
  })  : _storage = storage ?? const FlutterSecureStorage(),
        _api = api ?? ConsoleAuth();

  final FlutterSecureStorage _storage;
  final ConsoleAuth _api;

  Future<String> deviceId() async {
    var id = await _storage.read(key: _deviceKey);
    if (id != null && id.isNotEmpty) return id;
    id = _randomDeviceId();
    await _storage.write(key: _deviceKey, value: id);
    return id;
  }

  Future<AccountSession?> loadSession() async {
    final raw = await _storage.read(key: _storageKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return AccountSession(
        username: map['username'] as String? ?? '',
        password: map['password'] as String? ?? '',
        uid: (map['uid'] as num?)?.toInt() ?? 0,
        expireAt: (map['expire_at'] as num?)?.toInt() ?? 0,
        sessionToken: map['session_token'] as String? ?? '',
        deviceId: map['device_id'] as String? ?? '',
        banned: map['banned'] as bool? ?? false,
        permissionLevel: (map['permission_level'] as num?)?.toInt() ?? 0,
        email: map['email'] as String? ?? '',
      );
    } catch (_) {
      await _storage.delete(key: _storageKey);
      return null;
    }
  }

  Future<void> saveSession(AccountSession session) async {
    await _storage.write(
      key: _storageKey,
      value: jsonEncode(session.toJson()),
    );
  }

  Future<void> clearSession() async {
    await _storage.delete(key: _storageKey);
  }

  Future<AccountSession> login(String username, String password) async {
    final device = await deviceId();
    try {
      final session = await _api.login(
        username: username,
        password: password,
        deviceId: device,
      );
      await saveSession(session);
      return session;
    } catch (e) {
      if (e is ConsoleAuthException) rethrow;
      throw ConsoleAuth.mapNetwork(e);
    }
  }

  Future<void> sendRegisterCode(String email) async {
    final device = await deviceId();
    try {
      await _api.sendRegisterCode(email: email, deviceId: device);
    } catch (e) {
      if (e is ConsoleAuthException) rethrow;
      throw ConsoleAuth.mapNetwork(e);
    }
  }

  Future<AccountSession> register({
    required String username,
    required String password,
    required String email,
    required String verificationCode,
  }) async {
    final device = await deviceId();
    try {
      final session = await _api.register(
        username: username,
        password: password,
        email: email,
        verificationCode: verificationCode,
        deviceId: device,
      );
      await saveSession(session);
      return session;
    } catch (e) {
      if (e is ConsoleAuthException) rethrow;
      throw ConsoleAuth.mapNetwork(e);
    }
  }

  Future<AccountSession> refresh(AccountSession session) async {
    try {
      final updated = await _api.checkSession(session);
      await saveSession(updated);
      return updated;
    } catch (e) {
      if (e is ConsoleAuthException) rethrow;
      throw ConsoleAuth.mapNetwork(e);
    }
  }

  Future<void> sendPasswordChangeCode(String email) async {
    final device = await deviceId();
    try {
      await _api.sendPasswordChangeCode(email: email, deviceId: device);
    } catch (e) {
      if (e is ConsoleAuthException) rethrow;
      throw ConsoleAuth.mapNetwork(e);
    }
  }

  Future<AccountSession> updateUsername({
    required String oldUsername,
    required String newUsername,
    required String password,
  }) async {
    final session = await loadSession();
    if (session == null) {
      throw ConsoleAuthException('auth_failed', '未登录');
    }
    if (session.username.trim() != oldUsername.trim()) {
      throw ConsoleAuthException('auth_failed', '当前姓名不正确');
    }
    final trimmed = newUsername.trim();
    if (trimmed.isEmpty) {
      throw ConsoleAuthException('auth_failed', '新姓名不能为空');
    }
    try {
      final username = await _api.renameUser(
        session: session,
        newUsername: trimmed,
        password: password,
      );
      final updated = AccountSession(
        username: username,
        password: session.password,
        uid: session.uid,
        expireAt: session.expireAt,
        sessionToken: session.sessionToken,
        deviceId: session.deviceId,
        banned: session.banned,
        permissionLevel: session.permissionLevel,
        trafficPolicy: session.trafficPolicy,
        email: session.email,
      );
      await saveSession(updated);
      return updated;
    } catch (e) {
      if (e is ConsoleAuthException) rethrow;
      throw ConsoleAuth.mapNetwork(e);
    }
  }

  Future<AccountSession> updateEmail({
    required String currentEmail,
    required String newEmail,
    required String password,
  }) async {
    final session = await loadSession();
    if (session == null) {
      throw ConsoleAuthException('auth_failed', '未登录');
    }
    final next = newEmail.trim().toLowerCase();
    if (!next.contains('@')) {
      throw ConsoleAuthException('auth_failed', '请输入有效邮箱');
    }
    try {
      final email = await _api.changeEmail(
        session: session,
        currentEmail: currentEmail,
        newEmail: next,
        password: password,
      );
      final updated = AccountSession(
        username: session.username,
        password: session.password,
        uid: session.uid,
        expireAt: session.expireAt,
        sessionToken: session.sessionToken,
        deviceId: session.deviceId,
        banned: session.banned,
        permissionLevel: session.permissionLevel,
        trafficPolicy: session.trafficPolicy,
        email: email,
      );
      await saveSession(updated);
      return updated;
    } catch (e) {
      if (e is ConsoleAuthException) rethrow;
      throw ConsoleAuth.mapNetwork(e);
    }
  }

  Future<AccountSession> resetPasswordWithCode({
    required String email,
    required String verificationCode,
    required String newPassword,
  }) async {
    if (verificationCode.trim().length != 6) {
      throw ConsoleAuthException('auth_failed', '验证码须为 6 位');
    }
    if (newPassword.length < 6) {
      throw ConsoleAuthException('auth_failed', '新密码至少 6 位');
    }
    final session = await loadSession();
    if (session == null) {
      throw ConsoleAuthException('auth_failed', '未登录');
    }
    try {
      await _api.resetPasswordWithCode(
        session: session,
        email: email,
        verificationCode: verificationCode,
        newPassword: newPassword,
      );
      final storedEmail = session.email.trim().toLowerCase();
      final target = email.trim().toLowerCase();
      final updated = AccountSession(
        username: session.username,
        password: newPassword,
        uid: session.uid,
        expireAt: session.expireAt,
        sessionToken: session.sessionToken,
        deviceId: session.deviceId,
        banned: session.banned,
        permissionLevel: session.permissionLevel,
        trafficPolicy: session.trafficPolicy,
        email: storedEmail.isNotEmpty ? storedEmail : target,
      );
      await saveSession(updated);
      return updated;
    } catch (e) {
      if (e is ConsoleAuthException) rethrow;
      throw ConsoleAuth.mapNetwork(e);
    }
  }

  Future<AccountSession> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    final session = await loadSession();
    if (session == null) {
      throw ConsoleAuthException('auth_failed', '未登录');
    }
    try {
      await _api.changePassword(
        session: session,
        oldPassword: oldPassword,
        newPassword: newPassword,
      );
      final updated = AccountSession(
        username: session.username,
        password: newPassword,
        uid: session.uid,
        expireAt: session.expireAt,
        sessionToken: session.sessionToken,
        deviceId: session.deviceId,
        banned: session.banned,
        permissionLevel: session.permissionLevel,
        trafficPolicy: session.trafficPolicy,
        email: session.email,
      );
      await saveSession(updated);
      return updated;
    } catch (e) {
      if (e is ConsoleAuthException) rethrow;
      throw ConsoleAuth.mapNetwork(e);
    }
  }

  String _randomDeviceId() {
    final r = Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
