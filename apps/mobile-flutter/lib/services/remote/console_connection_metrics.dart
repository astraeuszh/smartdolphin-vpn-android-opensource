import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../features/auth/domain/account_session.dart';
import 'client_request_headers.dart';

class TunnelReadinessResult {
  const TunnelReadinessResult({
    required this.ip,
    required this.probeMs,
  });

  final String ip;
  final int probeMs;

  bool get isIpv4 => ip.contains('.');
  bool get isIpv6 => ip.contains(':');
}

class ConsoleConnectionMetrics {
  ConsoleConnectionMetrics({
    http.Client? client,
    http.Client Function()? probeClientFactory,
  })  : _client = client ?? http.Client(),
        _probeClientFactory = probeClientFactory ??
            (client == null ? http.Client.new : () => client),
        _closeProbeClient = client == null || probeClientFactory != null;

  static const _metricUrl =
      'https://api.smartdolphinvpn.com/api/client/connection-metrics';
  static const _probeUrls = [
    // Session UI has one primary exit address. Use IPv4-only providers here:
    // a dual-stack response from an IPv6-specialized provider can otherwise
    // replace the selected node's IPv4 address with an unrelated IPv6 route.
    'https://api.ipify.org?format=json',
    'https://checkip.amazonaws.com',
  ];

  final http.Client _client;
  final http.Client Function() _probeClientFactory;
  final bool _closeProbeClient;

  Future<TunnelReadinessResult> probe({
    required Duration timeout,
  }) async {
    // Never reuse the pre-tunnel keep-alive socket for the post-tunnel probe.
    // Android binds an existing socket to the network it was opened on, which
    // otherwise makes a healthy VPN keep reporting the physical exit IP.
    final probeClient = _probeClientFactory();
    final stopwatch = Stopwatch()..start();
    final completer = Completer<TunnelReadinessResult>();
    var completed = 0;

    for (final url in _probeUrls) {
      unawaited(probeClient
          .get(Uri.parse(url))
          .then((response) {
            if (response.statusCode >= 200 && response.statusCode < 300) {
              final ip = _parseIp(response.body);
              if (ip != null && !completer.isCompleted) {
                completer.complete(TunnelReadinessResult(
                  ip: ip,
                  probeMs: stopwatch.elapsedMilliseconds,
                ));
              }
            }
          })
          .catchError((_) {})
          .whenComplete(() {
            completed++;
            if (completed == _probeUrls.length && !completer.isCompleted) {
              completer
                  .completeError(StateError('tunnel readiness probe failed'));
            }
          }));
    }

    try {
      return await completer.future.timeout(timeout);
    } finally {
      if (_closeProbeClient) probeClient.close();
    }
  }

  Future<void> report(
    AccountSession session, {
    required String nodeId,
    required String protocol,
    required String outcome,
    required int totalMs,
    int? tunMs,
    int? coreMs,
    int? probeMs,
    bool dnsOk = false,
    bool? ipv4Ok,
    bool? ipv6Ok,
    String errorStage = '',
  }) async {
    if (session.sessionToken.trim().isEmpty) return;
    final response = await _client
        .post(
          Uri.parse(_metricUrl),
          headers: await ClientRequestHeaders.standard(
            bearerToken: session.sessionToken,
            json: true,
          ),
          body: jsonEncode({
            'node_id': nodeId,
            'protocol': protocol,
            'outcome': outcome,
            'total_ms': totalMs.clamp(0, 60000),
            if (tunMs != null) 'tun_ms': tunMs,
            if (coreMs != null) 'core_ms': coreMs,
            if (probeMs != null) 'probe_ms': probeMs,
            'dns_ok': dnsOk,
            'ipv4_ok': ipv4Ok,
            'ipv6_ok': ipv6Ok,
            'error_stage': errorStage,
          }),
        )
        .timeout(const Duration(seconds: 4));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('connection metric report failed');
    }
  }

  String? _parseIp(String body) {
    var candidate = body.trim();
    if (candidate.startsWith('{')) {
      try {
        final decoded = jsonDecode(candidate);
        if (decoded is Map) candidate = '${decoded['ip'] ?? ''}'.trim();
      } catch (_) {
        return null;
      }
    }
    if (candidate.length > 64 || candidate.contains(RegExp(r'\s'))) {
      return null;
    }
    final ipv4 = RegExp(r'^(?:\d{1,3}\.){3}\d{1,3}$');
    if (ipv4.hasMatch(candidate)) {
      return candidate;
    }
    return null;
  }
}
