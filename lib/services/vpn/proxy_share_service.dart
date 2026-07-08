import 'package:flutter/services.dart';

import '../../features/settings/domain/advanced_settings_config.dart';

/// 代理共享：VPN 连接后在本机开启 HTTP/SOCKS 代理供局域网设备使用。
class ProxyShareService {
  ProxyShareService._();

  static const _channel = MethodChannel('com.example.vpn/VpnChannel');

  static Future<void> sync({
    required bool vpnConnected,
    required bool enabled,
    required ProxyShareMode mode,
  }) async {
    if (!vpnConnected || !enabled) {
      await _channel.invokeMethod<void>('stopProxyShare');
      return;
    }
    await _channel.invokeMethod<void>('startProxyShare', {
      'mode': mode.name,
    });
  }
}
