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
      final result = await _channel
          .invokeMethod<Map<dynamic, dynamic>>('getNetworkTotals');
      if (result == null) return null;
      final rx = result['rx'];
      final tx = result['tx'];
      if (rx is! num || tx is! num) return null;
      return (rx: rx.toInt(), tx: tx.toInt());
    } catch (_) {
      return null;
    }
  }

  /// System ping latency in ms (Android `/system/bin/ping`).
  static Future<int?> pingMs(String host, {int count = 1}) async {
    if (!isAndroidNative) return null;
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'pingHost',
        {'host': host, 'count': count},
      );
      if (result == null) return null;
      final ms = result['ms'];
      if (ms is num && ms > 0) return ms.round();
    } catch (_) {}
    return null;
  }

  /// Packet loss percentage from system ping (0–100).
  static Future<double?> packetLossPercent(String host, {int count = 8}) async {
    if (!isAndroidNative) return null;
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'pingHost',
        {'host': host, 'count': count},
      );
      if (result == null) return null;
      final loss = result['loss'];
      if (loss is num) return loss.toDouble().clamp(0, 100);
    } catch (_) {}
    return null;
  }
}
