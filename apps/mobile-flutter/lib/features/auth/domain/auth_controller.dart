import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/runtime_platform.dart';
import '../../../platform/android/background_keep_alive.dart';
import '../../../services/remote/console_auth.dart';
import '../../session/domain/session_controller.dart';
import '../data/auth_repository.dart';
import 'account_session.dart';

enum AuthStatus {
  unknown,
  loading,
  guest,
  authenticated,
  pending,
  banned,
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

  AuthRepository get _repo => _ref.read(authRepositoryProvider);

  bool _isBannedAuthError(String code) => code == 'banned';

  Future<void> bootstrap() async {
    state = state.copyWith(status: AuthStatus.loading);
    final saved = await _repo.loadSession();
    if (saved == null || saved.username.isEmpty) {
      state = const AuthState(status: AuthStatus.guest);
      return;
    }
    try {
      final updated = await _repo.refresh(saved);
      _applySession(updated);
    } on ConsoleAuthException catch (e) {
      state = AuthState(
        status: _isBannedAuthError(e.code)
            ? AuthStatus.banned
            : saved.isPending
                ? AuthStatus.pending
                : AuthStatus.authenticated,
        session: saved,
        code: e.code,
        message: _isBannedAuthError(e.code) && e.message.isNotEmpty
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
    if (isAndroidNative) {
      unawaited(syncUninstallMeta(
        uid: session.uid,
        username: session.username,
        deviceId: session.deviceId,
      ));
    }
    if (session.banned) {
      unawaited(_ref.read(sessionControllerProvider.notifier).disconnect());
      state = AuthState(
        status: AuthStatus.banned,
        session: session,
        code: 'banned',
      );
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
    await _repo.clearSession();
    state = const AuthState(status: AuthStatus.guest);
  }

  Future<void> refreshSession() async {
    final saved = await _repo.loadSession() ?? state.session;
    if (saved == null) return;
    try {
      final updated = await _repo.refresh(saved);
      _applySession(updated);
    } on ConsoleAuthException catch (e) {
      if (_isBannedAuthError(e.code)) {
        _applySession(
          saved.copyWithRemote({
            'banned': true,
            'ban_reason': e.message,
          }),
        );
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
      unawaited(refreshSession());
      return s.canUseVpn;
    }
    try {
      final updated = await _repo.refresh(s);
      _applySession(updated);
      return updated.canUseVpn;
    } on ConsoleAuthException catch (e) {
      if (_isBannedAuthError(e.code)) {
        _applySession(
          s.copyWithRemote({'banned': true, 'ban_reason': e.message}),
        );
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
