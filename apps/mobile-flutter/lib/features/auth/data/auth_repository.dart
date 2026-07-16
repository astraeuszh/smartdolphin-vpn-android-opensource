import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../services/platform/hardware_device_id.dart';
import '../../../services/remote/console_auth.dart';
import '../../../services/remote/console_qr_auth.dart';
import '../domain/account_session.dart';
import '../domain/traffic_policy.dart';

const _storageKey = 'smartdolphin_auth_v2';
const _deviceKey = 'smartdolphin_device_id';
const _browserChallengeKey = 'smartdolphin_browser_login_challenge';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository();
});

class AuthRepository {
  AuthRepository({
    FlutterSecureStorage? storage,
    ConsoleAuth? api,
    ConsoleQrAuth? qrApi,
  })  : _storage = storage ?? const FlutterSecureStorage(),
        _api = api ?? ConsoleAuth(),
        _qrApi = qrApi ?? ConsoleQrAuth();

  final FlutterSecureStorage _storage;
  final ConsoleAuth _api;
  final ConsoleQrAuth _qrApi;

  Future<String> deviceId() async {
    var id = await _storage.read(key: _deviceKey);
    if (id != null && id.isNotEmpty) return id;
    id = _randomDeviceId();
    await _storage.write(key: _deviceKey, value: id);
    return id;
  }

  Future<void> saveBrowserLoginChallenge(String challengeId) =>
      _storage.write(key: _browserChallengeKey, value: challengeId);

  Future<String?> loadBrowserLoginChallenge() =>
      _storage.read(key: _browserChallengeKey);

  Future<void> clearBrowserLoginChallenge() =>
      _storage.delete(key: _browserChallengeKey);

  Future<AccountSession?> loadSession() async {
    final raw = await _storage.read(key: _storageKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return AccountSession(
        username: map['username'] as String? ?? '',
        password: map['password'] as String? ?? '',
        uid: (map['uid'] as num?)?.toInt() ?? 0,
        publicUid: map['public_uid'] as String? ?? '',
        expireAt: (map['expire_at'] as num?)?.toInt() ?? 0,
        sessionToken: map['session_token'] as String? ?? '',
        deviceId: map['device_id'] as String? ?? '',
        banned: map['banned'] as bool? ?? false,
        locked: map['locked'] as bool? ?? false,
        banReason: map['ban_reason'] as String? ?? '',
        permissionLevel: (map['permission_level'] as num?)?.toInt() ?? 0,
        trafficPolicy: TrafficPolicy.fromJson(map),
        email: map['email'] as String? ?? '',
        createdAt: (map['created_at'] as num?)?.toInt() ?? 0,
        subscribedAt: (map['subscribed_at'] as num?)?.toInt() ?? 0,
        mutedUntil: (map['muted_until'] as num?)?.toInt() ?? 0,
        notificationId:
            ((map['notification'] as Map?)?['id'] as num?)?.toInt() ?? 0,
        notificationType: '${(map['notification'] as Map?)?['type'] ?? ''}',
        notificationTitle: '${(map['notification'] as Map?)?['title'] ?? ''}',
        notificationBody: '${(map['notification'] as Map?)?['body'] ?? ''}',
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

  Future<void> setPresence(AccountSession session, bool online) async {
    await _api.setPresence(session, online);
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
    final hwId = await hardwareDeviceId();
    try {
      await _api.register(
        username: username,
        password: password,
        email: email,
        verificationCode: verificationCode,
        deviceId: device,
        hardwareDeviceId: hwId,
      );
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

  Future<Map<String, dynamic>> createQrLoginChallenge() async {
    final device = await deviceId();
    try {
      return await _qrApi.createChallenge(deviceId: device);
    } catch (e) {
      if (e is ConsoleAuthException) rethrow;
      throw ConsoleAuth.mapNetwork(e);
    }
  }

  Future<Map<String, dynamic>> pollQrLoginChallenge(String challengeId) async {
    final device = await deviceId();
    try {
      return await _qrApi.pollChallenge(
        deviceId: device,
        challengeId: challengeId,
      );
    } catch (e) {
      if (e is ConsoleAuthException) rethrow;
      throw ConsoleAuth.mapNetwork(e);
    }
  }

  Future<AccountSession> completeQrLogin(Map<String, dynamic> data) async {
    if (data['status'] == 'pending') {
      throw ConsoleAuthException('qr_pending', 'Waiting for QR confirmation');
    }
    if (data['ok'] != true) {
      throw ConsoleAuthException(
        (data['code'] as String?) ?? 'qr_failed',
        (data['error'] as String?) ?? 'QR sign-in failed',
      );
    }
    final device = await deviceId();
    final username = (data['username'] as String?)?.trim() ?? '';
    final session = AccountSession.fromJson(
      username: username,
      password: '',
      deviceId: device,
      data: data,
    );
    await saveSession(session);
    return session;
  }

  Future<void> approveQrLogin(
      AccountSession session, String challengeId) async {
    try {
      await _qrApi.approveChallenge(
        session: session,
        challengeId: challengeId,
      );
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
      throw ConsoleAuthException('auth_failed', 'Not signed in');
    }
    if (session.username.trim() != oldUsername.trim()) {
      throw ConsoleAuthException('auth_failed', 'Current name is incorrect');
    }
    final trimmed = newUsername.trim();
    if (trimmed.isEmpty) {
      throw ConsoleAuthException('auth_failed', 'New name cannot be empty');
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
        publicUid: session.publicUid,
        expireAt: session.expireAt,
        sessionToken: session.sessionToken,
        deviceId: session.deviceId,
        banned: session.banned,
        permissionLevel: session.permissionLevel,
        trafficPolicy: session.trafficPolicy,
        email: session.email,
        createdAt: session.createdAt,
        subscribedAt: session.subscribedAt,
        mutedUntil: session.mutedUntil,
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
      throw ConsoleAuthException('auth_failed', 'Not signed in');
    }
    final next = newEmail.trim().toLowerCase();
    if (!next.contains('@')) {
      throw ConsoleAuthException('auth_failed', 'Enter a valid email');
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
        publicUid: session.publicUid,
        expireAt: session.expireAt,
        sessionToken: session.sessionToken,
        deviceId: session.deviceId,
        banned: session.banned,
        permissionLevel: session.permissionLevel,
        trafficPolicy: session.trafficPolicy,
        email: email,
        createdAt: session.createdAt,
        subscribedAt: session.subscribedAt,
        mutedUntil: session.mutedUntil,
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
      throw ConsoleAuthException(
          'auth_failed', 'Verification code must be 6 digits');
    }
    if (newPassword.length < 6) {
      throw ConsoleAuthException(
          'auth_failed', 'New password must be at least 6 characters');
    }
    final session = await loadSession();
    if (session == null) {
      throw ConsoleAuthException('auth_failed', 'Not signed in');
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
        publicUid: session.publicUid,
        expireAt: session.expireAt,
        sessionToken: session.sessionToken,
        deviceId: session.deviceId,
        banned: session.banned,
        permissionLevel: session.permissionLevel,
        trafficPolicy: session.trafficPolicy,
        email: storedEmail.isNotEmpty ? storedEmail : target,
        createdAt: session.createdAt,
        subscribedAt: session.subscribedAt,
        mutedUntil: session.mutedUntil,
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
      throw ConsoleAuthException('auth_failed', 'Not signed in');
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
        publicUid: session.publicUid,
        expireAt: session.expireAt,
        sessionToken: session.sessionToken,
        deviceId: session.deviceId,
        banned: session.banned,
        permissionLevel: session.permissionLevel,
        trafficPolicy: session.trafficPolicy,
        email: session.email,
        createdAt: session.createdAt,
        subscribedAt: session.subscribedAt,
        mutedUntil: session.mutedUntil,
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
