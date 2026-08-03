import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/error/app_error_handler.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Keep the VPN UI portrait-only and avoid an orientation race during the
  // first Android activity resume.
  unawaited(SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
  ]));
  installAppErrorHandlers();
  runZonedGuarded(
    () => runApp(const ProviderScope(child: SmartDolphinApp())),
    (error, stack) {
      debugPrint('[AppError] zone: $error\n$stack');
    },
  );
}
