import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/error/app_error_handler.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  installAppErrorHandlers();
  runZonedGuarded(
    () => runApp(const ProviderScope(child: SmartDolphinApp())),
    (error, stack) {
      debugPrint('[AppError] zone: $error\n$stack');
    },
  );
}
