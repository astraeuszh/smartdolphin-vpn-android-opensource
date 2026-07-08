import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../platform/android/network_stats_channel.dart';
import '../../../services/vpn/clash_api_client.dart';
import '../../dashboard/domain/ip_info_provider.dart';
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
const _tickInterval = Duration(seconds: 1);

Future<int?> _measureLocalPing() => NetworkStatsChannel.pingMs('8.8.8.8');

double? _smoothMbps(double? previous, double sample) {
  const minMbps = 0.01;
  const alpha = 0.55;
  if (sample < minMbps) {
    return previous;
  }
  if (previous == null || previous < minMbps) {
    return sample;
  }
  return previous * (1 - alpha) + sample * alpha;
}

/// Local IP / geo / latency / throughput while VPN is disconnected.
/// IP & location refresh every 300s; latency & throughput every 1s.
final homeLocalStatsPeriodicProvider = StreamProvider.autoDispose<HomeLocalStats>((ref) async* {
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
    if (totals != null && lastSampleTime != null && lastRx != null && lastTx != null) {
      final elapsed = now.difference(lastSampleTime).inMilliseconds / 1000.0;
      if (elapsed >= 0.5 &&
          totals.rx >= lastRx &&
          totals.tx >= lastTx) {
        final rxDelta = (totals.rx - lastRx) / elapsed;
        final txDelta = (totals.tx - lastTx) / elapsed;
        downloadMbps = _smoothMbps(downloadMbps, (rxDelta * 8) / 1000000) ?? downloadMbps;
        uploadMbps = _smoothMbps(uploadMbps, (txDelta * 8) / 1000000) ?? uploadMbps;
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
      downloadMbps: downloadMbps > 0.01 ? downloadMbps : null,
      uploadMbps: uploadMbps > 0.01 ? uploadMbps : null,
    );

    await Future<void>.delayed(_tickInterval);
    secondsSinceIpRefresh += _tickInterval.inSeconds;
  }
});

final homeLocalStatsProvider = FutureProvider.autoDispose<HomeLocalStats>((ref) async {
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

/// Latency in ms, refreshed every 2s. When connected, ICMP can't traverse the
/// sing-box tunnel, so the REAL latency is measured via the Clash API
/// (`/proxies/proxy/delay`); when disconnected, a plain ICMP ping is used.
final homeSystemLatencyProvider = StreamProvider.autoDispose<int?>((ref) async* {
  while (true) {
    final connected =
        ref.read(sessionControllerProvider).status == SessionStatus.connected;
    if (connected) {
      yield await ClashApiClient.proxyDelayMs(timeoutMs: 4000);
    } else {
      yield await NetworkStatsChannel.pingMs('8.8.8.8');
    }
    // 3s (was 2s): fewer probes + fewer widget rebuilds = smoother UI.
    await Future<void>.delayed(const Duration(seconds: 3));
  }
});
