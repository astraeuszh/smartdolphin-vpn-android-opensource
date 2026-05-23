import 'package:flutter/services.dart';

import '../../core/platform/runtime_platform.dart';

class DeviceMemoryChannel {
  DeviceMemoryChannel._();

  static const _channel = MethodChannel('com.example.vpn/VpnChannel');

  /// 设备总物理内存（MB），非 Root、仅系统 API。
  static Future<int?> getTotalRamMb() async {
    if (!isAndroidNative) {
      return null;
    }
    try {
      final r = await _channel.invokeMethod<int>('getTotalRamMb');
      return r;
    } catch (_) {
      return null;
    }
  }
}
