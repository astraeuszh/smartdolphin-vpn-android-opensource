import 'dart:async';

import 'package:flutter/services.dart';

class SessionClock {
  SessionClock({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('com.example.vpn/VpnChannel');

  final MethodChannel _channel;

  Future<int> elapsedRealtime() async {
    try {
      final result = await _channel.invokeMethod<int>('elapsedRealtime');
      if (result != null) {
        return result;
      }
    } catch (_) {
      // ignore and fall through to wall clock fallback
    }
    return DateTime.now().millisecondsSinceEpoch;
  }

  Future<Duration> remaining({
    required int startElapsedMs,
    required Duration duration,
  }) async {
    final now = await elapsedRealtime();
    final elapsedMs = now - startElapsedMs;
    final remainingMs = duration.inMilliseconds - elapsedMs;
    if (remainingMs <= 0) {
      return Duration.zero;
    }
    return Duration(milliseconds: remainingMs);
  }

  Stream<Duration> countdownStream({
    required int startElapsedMs,
    required Duration duration,
    Duration tick = const Duration(seconds: 1),
  }) async* {
    while (true) {
      final remainingDuration =
          await remaining(startElapsedMs: startElapsedMs, duration: duration);
      yield remainingDuration;
      if (remainingDuration <= Duration.zero) {
        break;
      }
      await Future<void>.delayed(tick);
    }
  }

  /// Elapsed time since start. Uses one platform clock read, then wall-clock ticks
  /// (avoids ~60 MethodChannel calls/sec for the on-screen timer).
  Stream<Duration> elapsedStream({
    required int startElapsedMs,
    Duration tick = const Duration(milliseconds: 250),
  }) async* {
    final anchor = await elapsedRealtime();
    final wallAnchor = DateTime.now();
    while (true) {
      final wallElapsed = DateTime.now().difference(wallAnchor);
      final elapsedMs =
          (anchor - startElapsedMs) + wallElapsed.inMilliseconds;
      yield Duration(milliseconds: elapsedMs.clamp(0, 0x7FFFFFFF));
      await Future<void>.delayed(tick);
    }
  }
}
