import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../home/home_screen.dart';
import '../domain/auth_controller.dart';
import 'account_floating_banner.dart';
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
        return const _LoginGate();
      case AuthStatus.error:
        return auth.session == null ? const _LoginGate() : const _AuthedShell();
      case AuthStatus.authenticated:
      case AuthStatus.pending:
      case AuthStatus.banned:
      case AuthStatus.expired:
        return const _AuthedShell();
    }
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
  const _AuthedShell();

  @override
  Widget build(BuildContext context) {
    return const Stack(
      children: [
        HomeScreen(),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: AccountFloatingBanner(),
        ),
      ],
    );
  }
}
