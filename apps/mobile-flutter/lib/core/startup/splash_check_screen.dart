import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../errors/app_error.dart';
import '../errors/error_dialog.dart';
import 'startup_checker.dart';
import '../../features/auth/presentation/auth_gate_screen.dart';
import '../../services/logging/vpn_logger.dart';
import '../../theme/theme.dart';

/// Splash screen that runs startup self-check before showing main app.
class SplashCheckScreen extends ConsumerStatefulWidget {
  const SplashCheckScreen({super.key});

  @override
  ConsumerState<SplashCheckScreen> createState() => _SplashCheckScreenState();
}

class _SplashCheckScreenState extends ConsumerState<SplashCheckScreen> {
  AppError? _checkError;
  bool _checkDone = false;

  @override
  void initState() {
    super.initState();
    _wireLogCallback();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runCheck());
  }

  void _wireLogCallback() {
    setAppErrorLogCallback((level, message) {
      try {
        final logger = ref.read(vpnLoggerProvider);
        if (level == 'error') {
          logger.error(message);
        } else {
          logger.info(message);
        }
      } catch (_) {
        debugPrint('[AppError] $message');
      }
    });
  }

  Future<void> _runCheck() async {
    final err = await runStartupCheckAsync(ref);
    if (!mounted) return;
    setState(() {
      _checkError = err;
      _checkDone = true;
    });
    if (err != null) {
      await _showErrorAndWait(err);
    }
    if (!mounted) return;
    _navigateToHome();
  }

  Future<void> _showErrorAndWait(AppError err) async {
    logAppError(err, 'SplashCheckScreen');
    await showErrorDialog(
      context,
      message: err.message,
      errorCode: err.code,
      title: 'Startup Error',
      onClose: () {},
    );
  }

  void _navigateToHome() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const AuthGateScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.primaryContainer.withOpacity(0.3),
              theme.colorScheme.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 2),
              Icon(
                Icons.shield_outlined,
                size: 80,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                'SmartDolphinVPN',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
              const Spacer(flex: 1),
              if (!_checkDone)
                const SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(strokeWidth: 3),
                )
              else
                const SizedBox(height: 32),
              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }
}
