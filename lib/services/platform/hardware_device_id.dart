import 'package:flutter/services.dart';

const _channel = MethodChannel('com.example.vpn/VpnChannel');

/// Stable hardware-bound fingerprint (ANDROID_ID + device traits, SHA-256).
/// Survives app reinstall; only factory reset changes it on most devices.
Future<String> hardwareDeviceId() async {
  final id = await _channel.invokeMethod<String>('getHardwareDeviceId');
  if (id == null || id.length < 32) {
    throw StateError('hardware device id unavailable');
  }
  return id;
}
