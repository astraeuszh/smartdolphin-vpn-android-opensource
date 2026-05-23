import 'package:flutter/foundation.dart';

import 'error_codes.dart';

/// App error with code, message, details. Logs to VpnLogger when available.
class AppError implements Exception {
  AppError(
    this.code, {
    this.details = '',
    this.cause,
    String? displayMessage,
  }) : message = displayMessage ?? getErrorMessage(code);

  final int code;
  final String message;
  final String details;
  final Object? cause;

  String get formattedCode => formatErrorCode(code);

  @override
  String toString() => 'AppError($formattedCode: $message${details.isNotEmpty ? ' | $details' : ''})';
}

/// Callback for logging. Set by app to wire VpnLogger.
void Function(String level, String message)? _logCallback;

void setAppErrorLogCallback(void Function(String level, String message)? cb) {
  _logCallback = cb;
}

/// Log error with class name. Details go to log only; user sees brief message + code.
void logAppError(AppError err, String className) {
  final detail = err.details.isNotEmpty ? ' | ${err.details}' : '';
  final cause = err.cause != null ? ' | cause=${err.cause}' : '';
  final entry = 'ERROR_CODE=${err.formattedCode} | $className | ${err.message}$detail$cause';
  debugPrint('[AppError] $entry');
  _logCallback?.call('error', entry);
}
