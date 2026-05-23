import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;

/// TCP probes to public resolvers. Returns true when network looks unstable.
Future<bool> shouldOfferSmartStableProbe() async {
  if (kIsWeb) {
    return false;
  }
  const targets = [
    ('223.5.5.5', 443),
    ('1.1.1.1', 443),
    ('8.8.8.8', 443),
  ];
  final rtts = <int>[];
  var failures = 0;
  for (final (host, port) in targets) {
    final sw = Stopwatch()..start();
    try {
      final socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(milliseconds: 1500),
      );
      await socket.close();
      sw.stop();
      rtts.add(sw.elapsedMilliseconds);
    } catch (_) {
      failures++;
    }
  }
  if (rtts.isEmpty) {
    return failures >= 2;
  }
  final avg = rtts.reduce((a, b) => a + b) / rtts.length;
  var jitter = 0;
  if (rtts.length >= 2) {
    for (var i = 1; i < rtts.length; i++) {
      final d = (rtts[i] - rtts[i - 1]).abs();
      if (d > jitter) jitter = d;
    }
  }
  final loss = failures / targets.length;
  var score = 0;
  if (avg > 350) score++;
  if (jitter > 120) score++;
  if (loss >= 0.34) score++;
  return score >= 2;
}
