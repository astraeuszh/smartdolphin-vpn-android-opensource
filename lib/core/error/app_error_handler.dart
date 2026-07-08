import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Catches uncaught async/sync errors so one failure does not take down the process.
void installAppErrorHandlers() {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('[AppError] ${details.exceptionAsString()}');
    if (details.stack != null) {
      debugPrint(details.stack.toString());
    }
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('[AppError] uncaught: $error\n$stack');
    return true;
  };
}

/// Mixin for screens that run async work — skip [setState] after dispose.
mixin SafeScreenState<T extends StatefulWidget> on State<T> {
  bool _alive = true;

  bool get screenAlive => _alive;

  @override
  void dispose() {
    _alive = false;
    super.dispose();
  }

  void safeSetState(VoidCallback fn) {
    if (_alive && mounted) setState(fn);
  }
}
