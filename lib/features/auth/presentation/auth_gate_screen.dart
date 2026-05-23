import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../home/home_screen.dart';
import '../domain/auth_controller.dart';
import 'login_screen.dart';

/// 启动后根据控制台会话决定进入登录页或主页。
class AuthGateScreen extends ConsumerWidget {
  const AuthGateScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);

    switch (auth.status) {
      case AuthStatus.unknown:
      case AuthStatus.loading:
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      case AuthStatus.guest:
      case AuthStatus.error:
        return const _LoginGate();
      case AuthStatus.authenticated:
      case AuthStatus.pending:
      case AuthStatus.banned:
        return _AuthedShell(authMessage: _bannerMessage(auth));
    }
  }

  static String? _bannerMessage(AuthState auth) {
    if (auth.status == AuthStatus.pending) {
      return auth.message ?? '已注册，等待管理员开通';
    }
    if (auth.status == AuthStatus.banned) {
      return auth.message ?? '账户已封禁';
    }
    return null;
  }
}

/// 未登录时全屏登录/注册，禁止返回绕过。
class _LoginGate extends StatelessWidget {
  const _LoginGate();

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: const LoginScreen(),
    );
  }
}

class _AuthedShell extends StatelessWidget {
  const _AuthedShell({this.authMessage});

  final String? authMessage;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const HomeScreen(),
        if (authMessage != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Material(
              color: Colors.orange.shade900.withValues(alpha: 0.92),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Text(
                  authMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
