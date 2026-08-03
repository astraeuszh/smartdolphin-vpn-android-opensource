import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/vpn/clash_api_client.dart';
import '../../session/domain/session_controller.dart';
import '../../session/domain/session_status.dart';

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
  WebsiteTarget(
      id: 'youtube', name: 'YouTube', host: 'https://www.youtube.com'),
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
  WebsiteLatencyNotifier(this._ref) : super(const WebsiteLatencyState());

  final Ref _ref;

  static const _timeoutMsDisconnected = 1300;
  static const _timeoutMsConnected = 6000;
  static const _hardTimeout = Duration(seconds: 8);

  Future<void> testOne(String id) async {
    if (state.isTesting(id)) return;
    final target = websiteTargets.firstWhere((t) => t.id == id);
    state = WebsiteLatencyState(
      results: Map.from(state.results),
      testing: {...state.testing, id},
    );
    LatencyResult result;
    try {
      result = await _measureLatency(target)
          .timeout(_hardTimeout, onTimeout: () => const LatencyTimeout());
    } catch (_) {
      result = const LatencyError();
    }
    if (!mounted) return;
    state = WebsiteLatencyState(
      results: {...state.results, id: result},
      testing: {...state.testing}..remove(id),
    );
  }

  Future<void> testAll() async {
    for (final t in websiteTargets) {
      if (!mounted) return;
      await testOne(t.id);
    }
  }

  Future<LatencyResult> _measureLatency(WebsiteTarget target) async {
    final vpnConnected =
        _ref.read(sessionControllerProvider).status == SessionStatus.connected;

    // Raw TCP to a DNS-resolved edge IP often hits a local CDN (single-digit ms).
    // Through VPN, ask sing-box Clash API to probe the destination URL via proxy.
    if (vpnConnected) {
      final ms = await ClashApiClient.proxyDelayMs(
        testUrl: target.host,
        timeoutMs: 8000,
      );
      if (ms == null || ms <= 0) return const LatencyTimeout();
      return ms > _timeoutMsConnected
          ? const LatencyTimeout()
          : LatencySuccess(ms);
    }

    return _measureHttpHeadLatency(target.host);
  }

  Future<LatencyResult> _measureHttpHeadLatency(String url) async {
    final uri = Uri.parse(url);
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 2);
    final stopwatch = Stopwatch()..start();
    try {
      final request = await client.headUrl(uri);
      final response = await request.close();
      await response.drain<void>();
      stopwatch.stop();
      final ms = stopwatch.elapsedMilliseconds;
      return ms > _timeoutMsDisconnected
          ? const LatencyTimeout()
          : LatencySuccess(ms);
    } on TimeoutException {
      return const LatencyTimeout();
    } on SocketException {
      return const LatencyTimeout();
    } catch (_) {
      return const LatencyError();
    } finally {
      client.close(force: true);
    }
  }
}

final websiteLatencyProvider =
    StateNotifierProvider<WebsiteLatencyNotifier, WebsiteLatencyState>(
        (ref) => WebsiteLatencyNotifier(ref));
