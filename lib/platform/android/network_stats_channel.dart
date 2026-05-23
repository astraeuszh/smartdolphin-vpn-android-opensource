import 'package:flutter/services.dart';

import '../../core/platform/runtime_platform.dart';

class NetworkStatsChannel {
  NetworkStatsChannel._();

  static const _channel = MethodChannel('com.example.vpn/VpnChannel');

  static Future<({int rx, int tx})?> getTotals() async {
    if (!isAndroidNative) {
      return null;
    }
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('getNetworkTotals');
      if (result == null) return null;
      final rx = result['rx'];
      final tx = result['tx'];
      if (rx is! num || tx is! num) return null;
      return (rx: rx.toInt(), tx: tx.toInt());
    } catch (_) {
      return null;
    }
  }
}
