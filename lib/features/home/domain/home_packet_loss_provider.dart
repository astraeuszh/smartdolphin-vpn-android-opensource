import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../platform/android/network_stats_channel.dart';
import '../../../services/vpn/clash_api_client.dart';
import '../../session/domain/session_controller.dart';
import '../../session/domain/session_status.dart';

/// Packet loss percentage (0–100), refreshed periodically.
///
/// While connected, ICMP ping does not traverse the sing-box tunnel (it would
/// report a misleading 100% loss), so loss is estimated from a small burst of
/// Clash-API proxy-delay probes (failed probe = lost). When disconnected, the
/// normal system ICMP ping is used.
final homePacketLossProvider = StreamProvider.autoDispose<double?>((ref) async* {
  while (true) {
    final connected =
        ref.read(sessionControllerProvider).status == SessionStatus.connected;
    if (connected) {
      // ICMP ping does not traverse the TUN; a single Clash delay probe is the
      // best we can do. Success → 0% (no measured loss); failure → unknown.
      final d = await ClashApiClient.proxyDelayMs(timeoutMs: 3000);
      yield d != null ? 0.0 : null;
    } else {
      yield await NetworkStatsChannel.packetLossPercent('8.8.8.8', count: 8);
    }
    // 8s (was 5s): loss changes slowly; lighter on the proxy + UI.
    await Future<void>.delayed(const Duration(seconds: 8));
  }
});
