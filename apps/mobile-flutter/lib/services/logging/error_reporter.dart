import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/domain/auth_controller.dart';
import '../../services/logging/vpn_logger.dart';
import '../remote/console_feedback.dart';

class ErrorReporter {
  ErrorReporter(this._ref);

  final Ref _ref;

  Future<void> reportVpnError({
    required int errorCode,
    required String message,
    required String details,
  }) async {
    if (kIsWeb) return;
    final session = _ref.read(authControllerProvider).session;
    if (session == null || session.uid <= 0) return;
    try {
      final logger = _ref.read(vpnLoggerProvider);
      logger.system('vpn_error code=$errorCode details=$details');
      final snapshot = await logger.buildErrorFeedbackSnapshot();
      await ConsoleFeedback().submit(
        session: session,
        errorCode:
            '0x${errorCode.toRadixString(16).padLeft(8, '0').toUpperCase()}',
        message: message,
        logSnapshot: snapshot,
      );
    } catch (e) {
      debugPrint('[ErrorReporter] feedback failed: $e');
    }
  }
}

final errorReporterProvider =
    Provider<ErrorReporter>((ref) => ErrorReporter(ref));
