import 'dart:convert';

import 'package:http/http.dart' as http;

/// Minimal client for the embedded sing-box (dolphin-core) Clash API, exposed
/// on `127.0.0.1:9090` by the generated config.
///
/// ICMP ping does NOT work inside the sing-box TUN ("icmp is not supported by
/// default outbound: proxy"), which made the dashboard show latency `--` and
/// 100% packet loss while connected. The Clash API `/proxies/<tag>/delay`
/// endpoint measures the REAL latency through the active proxy instead — this
/// mirrors what the Windows client does via `GetDelay`.
class ClashApiClient {
  static const String _base = 'http://127.0.0.1:9090';

  /// Measures the proxy's delay (ms) to [testUrl] through the tunnel.
  /// Returns null on timeout/failure (treat as unreachable).
  static Future<int?> proxyDelayMs({
    String tag = 'proxy',
    String testUrl = 'http://www.gstatic.com/generate_204',
    int timeoutMs = 5000,
  }) async {
    try {
      final uri = Uri.parse('$_base/proxies/${Uri.encodeComponent(tag)}/delay')
          .replace(queryParameters: {
        'url': testUrl,
        'timeout': '$timeoutMs',
      });
      final resp =
          await http.get(uri).timeout(Duration(milliseconds: timeoutMs + 1500));
      if (resp.statusCode != 200) return null;
      final body = jsonDecode(resp.body);
      if (body is Map && body['delay'] is num) {
        final d = (body['delay'] as num).toInt();
        return d > 0 ? d : null;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Whether the Clash API is reachable (the core is up and serving).
  static Future<bool> isAvailable() async {
    try {
      final resp = await http
          .get(Uri.parse('$_base/version'))
          .timeout(const Duration(seconds: 2));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
