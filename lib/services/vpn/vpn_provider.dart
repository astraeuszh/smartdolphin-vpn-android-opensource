import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dolphin_core_port.dart';

/// Active VPN engine: Dolphin-Core (sing-box / libbox). Replaces OpenVPN.
/// The provider name is kept (`openVpnPortProvider`) so existing callers don't
/// need changes; it now returns the Dolphin-Core port.
final openVpnPortProvider = Provider<DolphinCorePort>((ref) {
  final port = DolphinCorePort();
  if (!kIsWeb) {
    port.initialize().catchError((error) {
      debugPrint('Failed to initialize Dolphin-Core: $error');
    });
  }
  ref.onDispose(port.dispose);
  return port;
});

/// Legacy alias kept for backward compatibility.
final vpnPortProvider = Provider<DolphinCorePort>((ref) {
  return ref.watch(openVpnPortProvider);
});
