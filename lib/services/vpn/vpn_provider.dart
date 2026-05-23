import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'openvpn_port.dart';
import 'models/vpn.dart';

/// Provider for OpenVPN port
final openVpnPortProvider = Provider<OpenVpnPort>((ref) {
  final port = OpenVpnPort();
  // Native OpenVPN / method channels are not used on web; skip init to avoid hangs.
  if (!kIsWeb) {
    port.initialize().catchError((error) {
      debugPrint('Failed to initialize OpenVPN: $error');
    });
  }
  ref.onDispose(port.dispose);
  return port;
});

/// Legacy VPN port provider for backward compatibility
/// Now returns OpenVPN port instead of WireGuard
final vpnPortProvider = Provider<OpenVpnPort>((ref) {
  return ref.watch(openVpnPortProvider);
});
