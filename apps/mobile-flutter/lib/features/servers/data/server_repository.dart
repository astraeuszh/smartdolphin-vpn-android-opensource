import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/server.dart';
import 'all_countries.dart';
import 'country_card.dart';
import 'static_servers.dart';
import '../../../services/storage/prefs.dart';

class ServerRepositoryException implements Exception {
  ServerRepositoryException({
    required this.message,
    this.cause,
    this.stackTrace,
  });

  final String message;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  String toString() {
    final buffer = StringBuffer('ServerRepositoryException: $message');
    if (cause != null) {
      buffer.write(' (cause: $cause)');
    }
    return buffer.toString();
  }
}

class ServerRepository {
  ServerRepository({PrefsStore? prefs}) : _prefs = prefs;

  final PrefsStore? _prefs;

  static const _cacheKey = 'servers_v6_smartdolphin';

  Future<List<Server>> loadServers() async {
    final list = List<Server>.from(smartDolphinStaticServers);
    developer.log(
      'Loaded ${list.length} SmartDolphin servers',
      name: 'ServerRepository',
    );
    await _saveCache(list);
    return list;
  }

  Future<List<CountryCard>> loadCountryCards() async {
    final servers = await loadServers();
    // Group our own nodes by country so a country with several nodes (e.g.
    // Hong Kong 1 + Hong Kong 2) yields one selectable card PER node instead of
    // collapsing them — keying by country code alone dropped all but the last.
    final ourByCountry = <String, List<Server>>{};
    for (final s in servers) {
      ourByCountry.putIfAbsent(s.countryCode.toUpperCase(), () => []).add(s);
    }
    final cards = <CountryCard>[];
    for (final (code, name) in allCountries) {
      final isPinned = code == 'HK' || code == 'US' || code == 'SG';
      final ours = ourByCountry[code];
      if (ours != null && ours.isNotEmpty) {
        for (final server in ours) {
          cards.add(CountryCard(
            countryCode: code,
            countryName: name,
            server: server,
            latencyMs: server.pingMs,
            isPinned: isPinned,
          ));
        }
      } else {
        cards.add(CountryCard(
          countryCode: code,
          countryName: name,
          server: null,
          isPinned: isPinned,
        ));
      }
    }
    return cards;
  }

  Future<List<Server>> _loadCachedServers() async {
    final prefs = _prefs;
    if (prefs == null) return const <Server>[];
    try {
      final raw = prefs.getString(_cacheKey);
      if (raw == null) return const <Server>[];
      final decoded = json.decode(raw);
      if (decoded is! List) return const <Server>[];
      final list = decoded
          .map((item) {
            if (item is Map) {
              return Server.fromJson(
                  Map<String, dynamic>.from(item as Map<dynamic, dynamic>));
            }
            return null;
          })
          .whereType<Server>()
          .toList(growable: false);
      final staticIds = smartDolphinStaticServers.map((s) => s.id).toSet();
      return list
          .where((s) => staticIds.contains(s.id))
          .toList(growable: false);
    } catch (_) {
      return const <Server>[];
    }
  }

  Future<void> _saveCache(List<Server> servers) async {
    final prefs = _prefs;
    if (prefs == null) return;
    try {
      await prefs.setString(
        _cacheKey,
        json.encode(servers.map((s) => s.toJson()).toList(growable: false)),
      );
    } catch (_) {}
  }
}

final serverRepositoryProvider = Provider<ServerRepository>((ref) {
  return ServerRepository(
    prefs: ref.watch(prefsStoreProvider).maybeWhen(
          data: (v) => v,
          orElse: () => null,
        ),
  );
});
