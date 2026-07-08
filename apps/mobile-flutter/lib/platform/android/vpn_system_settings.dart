import 'package:flutter/services.dart';

import '../../core/platform/runtime_platform.dart';

const _channel = MethodChannel('com.example.vpn/VpnChannel');

/// Whether Android system VPN settings have always-on VPN enabled for this app.
Future<bool> isAlwaysOnVpnEnabled() async {
  if (!isAndroidNative) return false;
  try {
    final enabled = await _channel.invokeMethod<bool>('isAlwaysOnVpnEnabled');
    return enabled ?? false;
  } catch (_) {
    return false;
  }
}

Future<bool> isVpnLockdownEnabled() async {
  if (!isAndroidNative) return false;
  try {
    final enabled = await _channel.invokeMethod<bool>('isVpnLockdownEnabled');
    return enabled ?? false;
  } catch (_) {
    return false;
  }
}

Future<bool> isStrictKillSwitchReady() async {
  if (!isAndroidNative) return true;
  final alwaysOn = await isAlwaysOnVpnEnabled();
  final lockdown = await isVpnLockdownEnabled();
  return alwaysOn && lockdown;
}
