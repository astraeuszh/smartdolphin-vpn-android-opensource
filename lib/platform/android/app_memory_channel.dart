import 'package:flutter/services.dart';

import '../../core/platform/runtime_platform.dart';

class AppMemoryChannel {
  AppMemoryChannel._();

  static const _channel = MethodChannel('com.example.vpn/VpnChannel');

  /// Process PSS in MB (Android ActivityManager.getProcessMemoryInfo).
  static Future<int?> getAppMemoryMb() async {
    if (!isAndroidNative) return null;
    try {
      final mb = await _channel.invokeMethod<int>('getAppMemoryMb');
      return mb;
    } catch (_) {
      return null;
    }
  }
}
