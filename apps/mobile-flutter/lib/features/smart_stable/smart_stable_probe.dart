import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;

import '../../services/vpn/clash_api_client.dart';

/// Returns true when the link looks unstable enough to offer SmartStable.
///
/// Primary signal is the REAL tunnel latency via the core's Clash API (the old
/// Dart-socket probe rides the tunnel itself, so it conflated tunnel and link
/// quality). The TCP probe is kept as a corroborating / fallback signal.
Future<bool> shouldOfferSmartStableProbe() async {
  if (kIsWeb) {
    return false;
  }
  // Sample the tunnel a couple of times via the Clash delay endpoint.
  var tunnelFailures = 0;
  final tunnelRtts = <int>[];
  for (var i = 0; i < 2; i++) {
    final d = await ClashApiClient.proxyDelayMs(timeoutMs: 2000);
    if (d == null) {
      tunnelFailures++;
    } else {
      tunnelRtts.add(d);
    }
  }
  if (tunnelFailures >= 2) return true; // tunnel basically dead → weak link
  if (tunnelRtts.isNotEmpty) {
    final avg = tunnelRtts.reduce((a, b) => a + b) / tunnelRtts.length;
    if (avg > 350 || tunnelFailures >= 1) return true;
  }
  return _tcpProbeBad();
}

/// Legacy TCP-connect probe to public resolvers (corroborating signal).
Future<bool> _tcpProbeBad() async {
  const targets = [
    ('223.5.5.5', 443),
    ('1.1.1.1', 443),
  ];
  final rtts = <int>[];
  var failures = 0;
  for (final (host, port) in targets) {
    final sw = Stopwatch()..start();
    try {
      final socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(milliseconds: 900),
      );
      await socket.close();
      sw.stop();
      rtts.add(sw.elapsedMilliseconds);
    } catch (_) {
      failures++;
    }
  }
  if (rtts.isEmpty) {
    return failures >= 1;
  }
  final avg = rtts.reduce((a, b) => a + b) / rtts.length;
  var jitter = 0;
  if (rtts.length >= 2) {
    for (var i = 1; i < rtts.length; i++) {
      final d = (rtts[i] - rtts[i - 1]).abs();
      if (d > jitter) jitter = d;
    }
  }
  final loss = failures / (targets.length + failures);
  var score = 0;
  if (avg > 180) score++;
  if (jitter > 50) score++;
  if (loss >= 0.2) score++;
  return score >= 1;
}
