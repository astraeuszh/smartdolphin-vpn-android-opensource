import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../platform/android/network_stats_channel.dart';
import '../../../services/vpn/clash_api_client.dart';
import '../../servers/domain/server_providers.dart';
import '../../session/domain/session_controller.dart';
import '../../session/domain/session_status.dart';

String? _activeNodeHost(Ref ref) {
  final session = ref.read(sessionControllerProvider);
  final serverId = session.serverId;
  final catalog = ref.read(serverCatalogProvider);
  if (serverId != null) {
    for (final server in catalog.servers) {
      if (server.id == serverId) {
        return server.ip ?? server.endpoint.split(':').first;
      }
    }
  }
  final selected = ref.read(selectedServerProvider);
  return selected?.ip ?? selected?.endpoint.split(':').first;
}

/// Packet loss percentage (0-100), refreshed periodically.
///
/// While connected, display node packet loss. A single Clash delay probe is not
/// packet loss and was causing false bad readings on otherwise reachable nodes.
final homePacketLossProvider =
    StreamProvider.autoDispose<double?>((ref) async* {
  while (true) {
    final connected =
        ref.read(sessionControllerProvider).status == SessionStatus.connected;
    if (connected) {
      final host = _activeNodeHost(ref);
      final loss = host != null
          ? await NetworkStatsChannel.packetLossPercent(host, count: 6)
          : null;
      if (loss != null) {
        yield loss;
      } else {
        final d = await ClashApiClient.proxyDelayMs(timeoutMs: 2500);
        yield d != null ? 0.0 : null;
      }
    } else {
      yield await NetworkStatsChannel.packetLossPercent('8.8.8.8', count: 8);
    }
    // 12s: loss changes slowly; lighter on the proxy, radio, and UI.
    await Future<void>.delayed(const Duration(seconds: 12));
  }
});
