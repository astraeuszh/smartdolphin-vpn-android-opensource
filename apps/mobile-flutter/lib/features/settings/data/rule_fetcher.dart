import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../domain/traffic_mode.dart';

/// Fetches built-in China IP rules from GitHub/CDN mirrors.
class RuleFetcher {
  RuleFetcher();

  /// Fetch China CIDR list. Returns list of "network netmask" for OpenVPN route.
  /// E.g. ["1.0.1.0 255.255.255.0", "1.0.2.0 255.255.254.0"]
  Future<List<String>> fetchBuiltInRules() async {
    for (final url in RuleDatabase.builtInUrls) {
      try {
        final resp = await http.get(Uri.parse(url)).timeout(
              const Duration(seconds: 15),
              onTimeout: () => throw Exception('Timeout'),
            );
        if (resp.statusCode != 200) continue;
        final lines = LineSplitter.split(resp.body)
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty && !s.startsWith('#'))
            .toList();
        final routes = <String>[];
        for (final line in lines) {
          final r = _cidrToRoute(line);
          if (r != null) routes.add(r);
        }
        debugPrint('[RuleFetcher] Fetched ${routes.length} routes from $url');
        return routes;
      } catch (e) {
        debugPrint('[RuleFetcher] Failed $url: $e');
      }
    }
    return [];
  }

  /// Convert CIDR (1.0.1.0/24) to "network netmask" for OpenVPN.
  String? _cidrToRoute(String cidr) {
    final parts = cidr.split('/');
    if (parts.length != 2) return null;
    final base = parts[0].trim();
    final prefix = int.tryParse(parts[1].trim());
    if (prefix == null || prefix < 0 || prefix > 32) return null;
    final mask = _prefixToMask(prefix);
    return '$base $mask';
  }

  String _prefixToMask(int prefix) {
    var mask = 0xFFFFFFFF << (32 - prefix);
    if (prefix == 0) mask = 0;
    final a = (mask >> 24) & 0xFF;
    final b = (mask >> 16) & 0xFF;
    final c = (mask >> 8) & 0xFF;
    final d = mask & 0xFF;
    return '$a.$b.$c.$d';
  }
}
