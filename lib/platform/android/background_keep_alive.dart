import 'package:flutter/services.dart';

import '../../core/platform/runtime_platform.dart';

const _channel = MethodChannel('com.example.vpn/VpnChannel');

/// Request user to exempt app from battery optimization (keeps VPN alive when screen off).
/// Opens system settings dialog. Call when user connects or from settings.
Future<void> requestBatteryOptimizationExemption() async {
  if (!isAndroidNative) return;
  try {
    await _channel.invokeMethod<void>('requestBatteryOptimizationExemption');
  } on PlatformException catch (e) {
    // User may dismiss dialog; log only
    assert(() {
      // ignore: avoid_print
      print('[BackgroundKeepAlive] Battery exemption: $e');
      return true;
    }());
  }
}

/// Returns true if app is exempt from battery optimization.
Future<bool> isIgnoringBatteryOptimizations() async {
  if (!isAndroidNative) return true;
  try {
    final r = await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations');
    return r ?? false;
  } on PlatformException {
    return false;
  }
}

/// Sync to native: when auto-connect (on launch or boot) is enabled, wake app on boot.
Future<void> setWakeOnBootEnabled(bool enabled) async {
  if (!isAndroidNative) return;
  try {
    await _channel.invokeMethod<void>('setWakeOnBootEnabled', enabled);
  } on PlatformException {
    // ignore
  }
}

/// Sync to native: has active VPN session (for NetworkChangeReceiver to wake app).
Future<void> setHasActiveSession(bool hasSession) async {
  if (!isAndroidNative) return;
  try {
    await _channel.invokeMethod<void>('setHasActiveSession', hasSession);
  } on PlatformException {
    // ignore
  }
}
