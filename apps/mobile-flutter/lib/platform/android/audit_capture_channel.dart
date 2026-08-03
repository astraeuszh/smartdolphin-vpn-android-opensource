import 'package:flutter/services.dart';

import '../../core/platform/runtime_platform.dart';

const _channel = MethodChannel('com.example.vpn/VpnChannel');

Future<void> syncNativeAuditCapture(String mode) async {
  if (!isAndroidNative) return;
  final normalized =
      const {'basic', 'security', 'enhanced'}.contains(mode) ? mode : 'basic';
  try {
    await _channel.invokeMethod<void>('setAuditCaptureMode', normalized);
  } catch (_) {
    // Older Android hosts do not expose this method. The server policy still
    // remains authoritative and the next upgraded host will receive it.
  }
}
