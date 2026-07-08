import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../platform/android/network_stats_channel.dart';
import '../../../services/vpn/clash_api_client.dart';
import '../../dashboard/domain/ip_info_provider.dart';
import '../../servers/domain/server_providers.dart';
import '../../session/domain/session_controller.dart';
import '../../session/domain/session_status.dart';

class HomeLocalStats {
  const HomeLocalStats({
    this.ip,
    this.region,
    this.city,
    this.countryCode,
    this.latencyMs,
    this.downloadMbps,
    this.uploadMbps,
  });

  final String? ip;
  final String? region;
  final String? city;
  final String? countryCode;
  final int? latencyMs;
  final double? downloadMbps;
  final double? uploadMbps;
}

const _ipRefreshInterval = Duration(seconds: 300);
const _tickInterval = Duration(seconds: 4);

Future<int?> _measureLocalPing() => NetworkStatsChannel.pingMs('8.8.8.8');

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

double? _smoothMbps(double? previous, double sample) {
  const minMbps = 0.05;
  const maxReasonableMobileMbps = 1000.0;
  const alpha = 0.3;
  if (sample < minMbps || sample > maxReasonableMobileMbps) {
    return previous;
  }
  if (previous == null || previous < minMbps) {
    return sample;
  }
  return previous * (1 - alpha) + sample * alpha;
}

/// Local IP / geo / latency / throughput while VPN is disconnected.
/// IP & location refresh every 300s; latency & throughput use a light cadence
/// to avoid constant radio wakeups while disconnected.
final homeLocalStatsPeriodicProvider =
    StreamProvider.autoDispose<HomeLocalStats>((ref) async* {
  if (ref.watch(sessionControllerProvider).status == SessionStatus.connected) {
    yield const HomeLocalStats();
    return;
  }

  var ipInfo = await fetchIpInfo();
  var latencyMs = await _measureLocalPing();
  var downloadMbps = 0.0;
  var uploadMbps = 0.0;

  int? lastRx;
  int? lastTx;
  DateTime? lastSampleTime;
  var secondsSinceIpRefresh = 0;

  while (true) {
    if (ref.read(sessionControllerProvider).status == SessionStatus.connected) {
      break;
    }

    if (secondsSinceIpRefresh >= _ipRefreshInterval.inSeconds) {
      ipInfo = await fetchIpInfo();
      secondsSinceIpRefresh = 0;
    }

    unawaited(_measureLocalPing().then((value) {
      if (value != null) {
        latencyMs = value;
      }
    }));

    final totals = await NetworkStatsChannel.getTotals();
    final now = DateTime.now();
    if (totals != null &&
        lastSampleTime != null &&
        lastRx != null &&
        lastTx != null) {
      final elapsed = now.difference(lastSampleTime).inMilliseconds / 1000.0;
      if (elapsed >= 0.5 && totals.rx >= lastRx && totals.tx >= lastTx) {
        final rxDelta = (totals.rx - lastRx) / elapsed;
        final txDelta = (totals.tx - lastTx) / elapsed;
        downloadMbps =
            _smoothMbps(downloadMbps, (rxDelta * 8) / 1000000) ?? downloadMbps;
        uploadMbps =
            _smoothMbps(uploadMbps, (txDelta * 8) / 1000000) ?? uploadMbps;
      }
    }
    if (totals != null) {
      lastRx = totals.rx;
      lastTx = totals.tx;
      lastSampleTime = now;
    }

    yield HomeLocalStats(
      ip: ipInfo.ip,
      region: ipInfo.region,
      city: ipInfo.city,
      countryCode: ipInfo.countryCode,
      latencyMs: latencyMs,
      downloadMbps: downloadMbps > 0.05 ? downloadMbps : null,
      uploadMbps: uploadMbps > 0.05 ? uploadMbps : null,
    );

    await Future<void>.delayed(_tickInterval);
    secondsSinceIpRefresh += _tickInterval.inSeconds;
  }
});

final homeLocalStatsProvider =
    FutureProvider.autoDispose<HomeLocalStats>((ref) async {
  final ipInfo = await ref.watch(ipInfoProvider.future);
  final ping = await _measureLocalPing();
  return HomeLocalStats(
    ip: ipInfo.ip,
    region: ipInfo.region,
    city: ipInfo.city,
    countryCode: ipInfo.countryCode,
    latencyMs: ping,
  );
});

/// Latency in ms, refreshed periodically.
///
/// When connected, display the selected node RTT instead of the Clash proxy
/// delay target. The proxy delay includes route rules, target reachability and
/// protocol retries, so it can falsely show 1000-2500ms while the node itself
/// is actually reachable in the 200-400ms range.
final homeSystemLatencyProvider =
    StreamProvider.autoDispose<int?>((ref) async* {
  while (true) {
    final connected =
        ref.read(sessionControllerProvider).status == SessionStatus.connected;
    if (connected) {
      final host = _activeNodeHost(ref);
      final nodePing = host != null
          ? await NetworkStatsChannel.pingMs(host, count: 3)
          : null;
      yield nodePing ?? await ClashApiClient.proxyDelayMs(timeoutMs: 2500);
    } else {
      yield await NetworkStatsChannel.pingMs('8.8.8.8');
    }
    // 5s: fewer probes + fewer widget rebuilds = smoother UI and lower power.
    await Future<void>.delayed(const Duration(seconds: 5));
  }
});
