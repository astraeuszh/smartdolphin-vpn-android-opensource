import 'package:flutter/foundation.dart';

/// Native Android app (not Flutter Web). Safe where `dart:io` [Platform] is unavailable.
bool get isAndroidNative =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
