import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 网站延迟测试目标
class WebsiteTarget {
  const WebsiteTarget({
    required this.id,
    required this.name,
    required this.host,
  });
  final String id;
  final String name;
  final String host;
}

const websiteTargets = [
  WebsiteTarget(id: 'google', name: 'Google', host: 'https://www.google.com'),
  WebsiteTarget(id: 'amazon', name: 'Amazon', host: 'https://www.amazon.com'),
  WebsiteTarget(id: 'youtube', name: 'YouTube', host: 'https://www.youtube.com'),
];

/// 延迟测试结果：成功(ms)、超时、失败
sealed class LatencyResult {}

class LatencySuccess implements LatencyResult {
  const LatencySuccess(this.ms);
  final int ms;
}

class LatencyTimeout implements LatencyResult {
  const LatencyTimeout();
}

class LatencyError implements LatencyResult {
  const LatencyError();
}

class WebsiteLatencyState {
  const WebsiteLatencyState({
    this.results = const {},
    this.testing = const {},
  });
  final Map<String, LatencyResult> results;
  final Set<String> testing;

  LatencyResult? result(String id) => results[id];
  bool isTesting(String id) => testing.contains(id);
}

class WebsiteLatencyNotifier extends StateNotifier<WebsiteLatencyState> {
  WebsiteLatencyNotifier() : super(const WebsiteLatencyState());

  static const _timeoutMs = 1300;

  Future<void> testOne(String id) async {
    final target = websiteTargets.firstWhere((t) => t.id == id);
    state = WebsiteLatencyState(
      results: Map.from(state.results),
      testing: {...state.testing, id},
    );
    try {
      final result = await _measureLatency(target.host);
      state = WebsiteLatencyState(
        results: {...state.results, id: result},
        testing: {...state.testing}..remove(id),
      );
    } catch (_) {
      state = WebsiteLatencyState(
        results: {...state.results, id: const LatencyError()},
        testing: {...state.testing}..remove(id),
      );
    }
  }

  Future<void> testAll() async {
    for (final t in websiteTargets) {
      await testOne(t.id);
    }
  }

  Future<LatencyResult> _measureLatency(String url) async {
    final uri = Uri.parse(url);
    final host = uri.host;
    if (host.isEmpty) {
      return const LatencyError();
    }
    final port = uri.hasPort ? uri.port : 443;
    final stopwatch = Stopwatch()..start();
    try {
      final socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 3),
      );
      socket.destroy();
      stopwatch.stop();
      final ms = stopwatch.elapsedMilliseconds;
      if (ms > _timeoutMs) {
        return const LatencyTimeout();
      }
      return LatencySuccess(ms);
    } on TimeoutException {
      return const LatencyTimeout();
    } on SocketException {
      return const LatencyTimeout();
    } catch (_) {
      return const LatencyTimeout();
    }
  }
}

final websiteLatencyProvider =
    StateNotifierProvider<WebsiteLatencyNotifier, WebsiteLatencyState>(
        (ref) => WebsiteLatencyNotifier());
