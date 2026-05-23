import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../errors/app_error.dart';
import '../errors/error_codes.dart';
import '../../features/settings/data/settings_repository.dart';
import '../../services/logging/vpn_logger.dart';
import '../../services/storage/prefs.dart';

/// Async startup self-check. Returns null on success, AppError on failure.
Future<AppError?> runStartupCheckAsync(dynamic ref) async {
  try {
    // 1. Prefs must be ready
    final prefs = await ref.read(prefsStoreProvider.future);

    // 2. Settings load (non-fatal; use defaults on failure)
    final repo = ref.read(settingsRepositoryProvider);
    if (repo != null) {
      try {
        repo.loadProtocol();
        repo.loadRouting();
        repo.loadLog();
      } catch (e) {
        ref.read(vpnLoggerProvider).warn('StartupChecker: settings load - $e');
      }
    }

    return null;
  } catch (e, st) {
    debugPrint('[StartupChecker] Failed: $e\n$st');
    final err = AppError(ecStartupInitFailed, details: e.toString(), cause: e);
    logAppError(err, 'StartupChecker');
    return err;
  }
}
