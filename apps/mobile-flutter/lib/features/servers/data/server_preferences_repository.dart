import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/storage/prefs.dart';

/// Per-server speed test cache (Mbps, ms).
class ServerSpeedCache {
  const ServerSpeedCache({
    required this.downloadMbps,
    required this.uploadMbps,
    this.pingMs,
  });

  final double downloadMbps;
  final double uploadMbps;
  final int? pingMs;

  Map<String, dynamic> toJson() => {
        'downloadMbps': downloadMbps,
        'uploadMbps': uploadMbps,
        'pingMs': pingMs,
      };

  static ServerSpeedCache? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final d = (json['downloadMbps'] as num?)?.toDouble();
    final u = (json['uploadMbps'] as num?)?.toDouble();
    if (d == null || u == null) return null;
    return ServerSpeedCache(
      downloadMbps: d,
      uploadMbps: u,
      pingMs: (json['pingMs'] as num?)?.toInt(),
    );
  }
}

class ServerPreferencesRepository {
  ServerPreferencesRepository(this._prefs);

  final PrefsStore _prefs;

  static const _favoritesKey = 'server_favorites';
  static const _lastServerKey = 'server_last_selected';
  static const _speedCacheKey = 'server_speed_cache';

  Map<String, ServerSpeedCache> loadServerSpeedCache() {
    final raw = _prefs.getString(_speedCacheKey);
    if (raw == null) return {};
    try {
      final map = json.decode(raw) as Map<String, dynamic>;
      final result = <String, ServerSpeedCache>{};
      for (final e in map.entries) {
        final val = e.value;
        final cached = val is Map ? ServerSpeedCache.fromJson(Map<String, dynamic>.from(val)) : null;
        if (cached != null) result[e.key.toString()] = cached;
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  Future<void> saveServerSpeedCache(String serverId, ServerSpeedCache cache) async {
    final current = loadServerSpeedCache();
    current[serverId] = cache;
    await _prefs.setString(_speedCacheKey, json.encode(
      current.map((k, v) => MapEntry(k, v.toJson())),
    ));
  }

  Set<String> loadFavorites() {
    final raw = _prefs.getString(_favoritesKey);
    if (raw == null) return <String>{};
    try {
      final decoded = (json.decode(raw) as List<dynamic>)
          .map((e) => e as String)
          .toSet();
      return decoded;
    } catch (_) {
      return <String>{};
    }
  }

  Future<void> saveFavorites(Set<String> favorites) async {
    final encoded = json.encode(favorites.toList());
    await _prefs.setString(_favoritesKey, encoded);
  }

  String? loadLastServerId() => _prefs.getString(_lastServerKey);

  Future<void> saveLastServerId(String id) =>
      _prefs.setString(_lastServerKey, id);
}

final serverPreferencesRepositoryProvider =
    Provider<ServerPreferencesRepository?>((ref) {
  final prefsAsync = ref.watch(prefsStoreProvider);
  return prefsAsync.whenOrNull(data: ServerPreferencesRepository.new);
});
