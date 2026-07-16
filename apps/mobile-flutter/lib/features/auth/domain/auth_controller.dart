import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/runtime_platform.dart';
import '../../../platform/android/background_keep_alive.dart';
import '../../../services/remote/console_auth.dart';
import '../../../services/notifications/session_notification_service.dart';
import '../../../services/storage/prefs.dart';
import '../../session/domain/session_controller.dart';
import '../../settings/data/support_chat_repository.dart';
import '../data/auth_repository.dart';
import 'account_session.dart';

enum AuthStatus {
  unknown,
  loading,
  guest,
  authenticated,
  pending,
  banned,
  expired,
  error
}

class AuthState {
  const AuthState({
    this.status = AuthStatus.unknown,
    this.session,
    this.message,
    this.code,
  });

  final AuthStatus status;
  final AccountSession? session;
  final String? message;
  final String? code;

  AuthState copyWith({
    AuthStatus? status,
    AccountSession? session,
    String? message,
    String? code,
  }) {
    return AuthState(
      status: status ?? this.status,
      session: session ?? this.session,
      message: message,
      code: code,
    );
  }
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController(ref);
});

class AuthController extends StateNotifier<AuthState> {
  AuthController(this._ref) : super(const AuthState()) {
    bootstrap();
  }

  final Ref _ref;
  Future<void>? _refreshInFlight;
  DateTime? _lastRefreshAt;

  AuthRepository get _repo => _ref.read(authRepositoryProvider);

  bool _isBannedAuthError(String code) => code == 'banned';
  bool _isExpiredAuthError(String code) => code == 'account_expired';
  bool _isDeletedAuthError(String code) => code == 'account_deleted';
  bool _isRevokedAuthError(String code) =>
      _isDeletedAuthError(code) || code == 'unauthorized';

  Future<void> _clearDeletedAccount([AccountSession? account]) async {
    final current = account ?? state.session ?? await _repo.loadSession();
    unawaited(_ref
        .read(sessionControllerProvider.notifier)
        .disconnect(userInitiated: false));
    if (current != null) {
      try {
        await SupportChatRepository.clearAccount(current);
      } catch (_) {
        // Cache cleanup must never keep a revoked account authenticated.
      }
    }
    await _repo.clearSession();
    state = const AuthState(status: AuthStatus.guest);
  }

  Future<void> bootstrap() async {
    state = state.copyWith(status: AuthStatus.loading);
    final saved = await _repo.loadSession();
    if (saved == null || saved.username.isEmpty) {
      state = const AuthState(status: AuthStatus.guest);
      return;
    }
    _applySession(saved);
    try {
      final updated = await _repo.refresh(saved);
      _applySession(updated);
    } on ConsoleAuthException catch (e) {
      if (_isRevokedAuthError(e.code)) {
        await _clearDeletedAccount(saved);
        return;
      }
      state = AuthState(
        status: _isBannedAuthError(e.code)
            ? AuthStatus.banned
            : _isExpiredAuthError(e.code)
                ? AuthStatus.expired
                : saved.isPending
                    ? AuthStatus.pending
                    : AuthStatus.authenticated,
        session: saved,
        code: e.code,
        message: (_isBannedAuthError(e.code) || _isExpiredAuthError(e.code)) &&
                e.message.isNotEmpty
            ? e.message
            : null,
      );
    } catch (e) {
      state = AuthState(
        status: saved.isPending ? AuthStatus.pending : AuthStatus.authenticated,
        session: saved,
        message: e.toString(),
      );
    }
  }

  void _applySession(AccountSession session) {
    unawaited(_showAccountNotification(session));
    if (isAndroidNative) {
      unawaited(syncUninstallMeta(
        uid: session.uid,
        username: session.username,
        deviceId: session.deviceId,
      ));
    }
    if (session.banned ||
        session.locked ||
        session.trafficPolicy.isAccountLocked) {
      unawaited(_ref
          .read(sessionControllerProvider.notifier)
          .disconnect(userInitiated: false));
      state = AuthState(
        status: AuthStatus.banned,
        session: session,
        code: session.banned ? 'banned' : 'risk_locked',
        message: session.banned
            ? null
            : 'Account locked after 30 violations. Contact support to review this restriction.',
      );
      return;
    }
    if (session.isExpired) {
      unawaited(_ref
          .read(sessionControllerProvider.notifier)
          .disconnect(userInitiated: false));
      state = const AuthState(
        status: AuthStatus.expired,
        code: 'account_expired',
        message: '当前权限已到期，请联系管理员续权。',
      ).copyWith(session: session);
      return;
    }
    if (session.isPending) {
      state = AuthState(
        status: AuthStatus.pending,
        session: session,
        code: 'pending_vpn',
      );
      return;
    }
    state = AuthState(status: AuthStatus.authenticated, session: session);
  }

  Future<void> _showAccountNotification(AccountSession session) async {
    if (session.notificationId <= 0 ||
        session.notificationTitle.trim().isEmpty ||
        session.notificationBody.trim().isEmpty) {
      return;
    }
    final prefs = await PrefsStore.create();
    final key = 'account_notification.last.${session.uid}';
    final seen = int.tryParse(prefs.getString(key) ?? '') ?? 0;
    if (session.notificationId <= seen) return;
    final service = _ref.read(sessionNotificationServiceProvider);
    await service.initialize();
    await service.showAccountMessage(
      id: session.notificationId,
      title: session.notificationTitle,
      body: session.notificationBody,
    );
    await prefs.setString(key, session.notificationId.toString());
  }

  Future<void> login(String username, String password) async {
    state = state.copyWith(status: AuthStatus.loading, message: null);
    try {
      final session = await _repo.login(username, password);
      _applySession(session);
    } on ConsoleAuthException catch (e) {
      state =
          AuthState(status: AuthStatus.error, code: e.code, message: e.message);
    } catch (e) {
      state = AuthState(status: AuthStatus.error, message: e.toString());
    }
  }

  Future<void> register({
    required String displayName,
    required String email,
    required String password,
    required String verificationCode,
  }) async {
    state = state.copyWith(status: AuthStatus.loading, message: null);
    try {
      final session = await _repo.register(
        username: displayName,
        password: password,
        email: email,
        verificationCode: verificationCode,
      );
      _applySession(session);
    } on ConsoleAuthException catch (e) {
      state =
          AuthState(status: AuthStatus.error, code: e.code, message: e.message);
    } catch (e) {
      state = AuthState(status: AuthStatus.error, message: e.toString());
    }
  }

  Future<void> logout() async {
    final current = state.session;
    if (current != null && current.sessionToken.isNotEmpty) {
      try {
        await _repo.setPresence(current, false);
      } catch (_) {
        // Logout must always clear local credentials even if the network is
        // unavailable. The server-side presence TTL is the fallback.
      }
    }
    if (current != null) {
      try {
        await SupportChatRepository.clearAccount(current);
      } catch (_) {
        // Logout remains authoritative even if a media cache file is locked.
      }
    }
    await _repo.clearSession();
    state = const AuthState(status: AuthStatus.guest);
  }

  Future<void> setForegroundPresence(bool online) async {
    var current = state.session ?? await _repo.loadSession();
    if (current == null || current.sessionToken.isEmpty) return;
    try {
      await _repo.setPresence(current, online);
    } on ConsoleAuthException catch (error) {
      if (error.code != 'unauthorized' || !online) return;
      // A 401 is authoritative for the stored login. Keeping the old session
      // here made deleted accounts and their local support history remain
      // visible indefinitely while every authenticated request failed.
      await _clearDeletedAccount(current);
    }
  }

  Future<void> refreshSession({bool force = false}) async {
    final now = DateTime.now();
    final last = _lastRefreshAt;
    if (_refreshInFlight != null) {
      await _refreshInFlight;
      return;
    }
    if (!force &&
        last != null &&
        now.difference(last) < const Duration(minutes: 2)) {
      return;
    }
    _refreshInFlight = _refreshSessionNow();
    try {
      await _refreshInFlight;
    } finally {
      _refreshInFlight = null;
      _lastRefreshAt = DateTime.now();
    }
  }

  Future<void> _refreshSessionNow() async {
    final saved = await _repo.loadSession() ?? state.session;
    if (saved == null) return;
    try {
      final updated = await _repo.refresh(saved);
      _applySession(updated);
    } on ConsoleAuthException catch (e) {
      if (_isRevokedAuthError(e.code)) {
        await _clearDeletedAccount(saved);
        return;
      }
      if (_isBannedAuthError(e.code)) {
        _applySession(
          saved.copyWithRemote({
            'banned': true,
            'ban_reason': e.message,
          }),
        );
        return;
      }
      if (_isExpiredAuthError(e.code)) {
        unawaited(_ref
            .read(sessionControllerProvider.notifier)
            .disconnect(userInitiated: false));
        state = AuthState(
            status: AuthStatus.expired,
            session: saved,
            code: e.code,
            message: '当前权限已到期，请联系管理员续权。');
        return;
      }
      state = AuthState(
        status: saved.isPending ? AuthStatus.pending : AuthStatus.authenticated,
        session: saved,
        code: e.code,
      );
    }
  }

  Future<void> applySessionUpdate(AccountSession session) async {
    await _repo.saveSession(session);
    _applySession(session);
  }

  Future<void> updateUsername({
    required String oldUsername,
    required String newUsername,
    required String password,
  }) async {
    final updated = await _repo.updateUsername(
      oldUsername: oldUsername,
      newUsername: newUsername,
      password: password,
    );
    _applySession(updated);
  }

  Future<void> updateEmail({
    required String currentEmail,
    required String newEmail,
    required String password,
  }) async {
    final updated = await _repo.updateEmail(
      currentEmail: currentEmail,
      newEmail: newEmail,
      password: password,
    );
    _applySession(updated);
  }

  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    final updated = await _repo.changePassword(
      oldPassword: oldPassword,
      newPassword: newPassword,
    );
    _applySession(updated);
  }

  Future<void> resetPasswordWithCode({
    required String email,
    required String verificationCode,
    required String newPassword,
  }) async {
    final updated = await _repo.resetPasswordWithCode(
      email: email,
      verificationCode: verificationCode,
      newPassword: newPassword,
    );
    _applySession(updated);
  }

  Future<bool> ensureVpnAccess() async {
    final s = state.session;
    if (s == null) return false;
    if (s.banned) return false;
    if (s.sessionToken.isNotEmpty) {
      await refreshSession(force: true);
      return state.session?.canUseVpn ?? s.canUseVpn;
    }
    try {
      final updated = await _repo.refresh(s);
      _applySession(updated);
      return updated.canUseVpn;
    } on ConsoleAuthException catch (e) {
      if (_isRevokedAuthError(e.code)) {
        await _clearDeletedAccount(s);
        return false;
      }
      if (_isBannedAuthError(e.code)) {
        _applySession(
          s.copyWithRemote({'banned': true, 'ban_reason': e.message}),
        );
        return false;
      }
      if (_isExpiredAuthError(e.code)) {
        unawaited(_ref
            .read(sessionControllerProvider.notifier)
            .disconnect(userInitiated: false));
        state = AuthState(
            status: AuthStatus.expired,
            session: s,
            code: e.code,
            message: '当前权限已到期，请联系管理员续权。');
        return false;
      }
      state = AuthState(
        status: s.isPending ? AuthStatus.pending : AuthStatus.authenticated,
        session: s,
        code: e.code,
      );
      return s.canUseVpn;
    } catch (_) {
      if (s.banned) return false;
      return s.canUseVpn;
    }
  }

  Future<void> approveQrLogin(String challengeId) async {
    final current = state.session;
    if (current == null) {
      throw ConsoleAuthException('auth_failed', '');
    }
    var s = current;
    try {
      s = await _repo.refresh(s);
      _applySession(s);
    } catch (_) {
      // refresh failed — approve still tries uid+token+password fallback on server
    }
    await _repo.approveQrLogin(s, challengeId);
  }

  Future<void> completeQrLogin(Map<String, dynamic> data) async {
    state = state.copyWith(status: AuthStatus.loading, message: null);
    try {
      final session = await _repo.completeQrLogin(data);
      _applySession(session);
    } on ConsoleAuthException catch (e) {
      if (e.code == 'qr_pending') return;
      state =
          AuthState(status: AuthStatus.error, code: e.code, message: e.message);
    } catch (e) {
      state = AuthState(status: AuthStatus.error, message: e.toString());
    }
  }
}
