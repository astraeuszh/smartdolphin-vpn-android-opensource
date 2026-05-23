import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'server.dart';
import '../../../l10n/country_names.dart';
import '../data/all_countries.dart';
import '../data/country_card.dart';
import '../data/server_preferences_repository.dart';
import '../data/server_repository.dart';
import '../data/static_servers.dart';

class ServerCatalogState {
  const ServerCatalogState({
    this.countryCards = const [],
    this.favorites = const <String>{},
    this.latencyMs = const {},
    this.query = '',
    this.isLoading = true,
    this.error,
    this.connectedServerId,
  });

  final List<CountryCard> countryCards;
  final Set<String> favorites;
  final Map<String, int> latencyMs;
  final String query;
  final bool isLoading;
  final String? error;
  final String? connectedServerId;

  /// 从可连接的国家卡片中提取 Server 列表（用于兼容 ServerSelection 等）
  List<Server> get servers => countryCards
      .where((c) => c.server != null)
      .map((c) => c.server!)
      .toList();

  /// 可连接节点的 Server 列表，按 sortedCountryCards 顺序（用于默认选择）
  List<Server> get connectableServers => sortedCountryCards
      .where((c) => c.isConnectable && c.server != null)
      .map((c) => c.server!)
      .toList();

  /// HK、美国、新加坡固定前三；可连接的按延迟排序；超时/无节点放最后
  List<CountryCard> get sortedCountryCards {
    final q = query.trim().toLowerCase();
    var filtered = countryCards;
    if (q.isNotEmpty) {
      filtered = countryCards
          .where((c) => countryMatchesSearch(q, c.countryCode))
          .toList();
    }
    final sorted = [...filtered];
    sorted.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      if (a.isPinned && b.isPinned) {
        final pa = _pinPriority(a.countryCode);
        final pb = _pinPriority(b.countryCode);
        if (pa != pb) return pa.compareTo(pb);
      }
      if (a.isConnectable != b.isConnectable) return a.isConnectable ? -1 : 1;
      final la = a.latencyMs ?? 9999;
      final lb = b.latencyMs ?? 9999;
      return la.compareTo(lb);
    });
    return sorted;
  }

  ServerCatalogState copyWith({
    List<CountryCard>? countryCards,
    Set<String>? favorites,
    Map<String, int>? latencyMs,
    String? query,
    bool? isLoading,
    String? error,
    Object? connectedServerId = _sentinel,
  }) {
    return ServerCatalogState(
      countryCards: countryCards ?? this.countryCards,
      favorites: favorites ?? this.favorites,
      latencyMs: latencyMs ?? this.latencyMs,
      query: query ?? this.query,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
      connectedServerId: identical(connectedServerId, _sentinel)
          ? this.connectedServerId
          : connectedServerId as String?,
    );
  }
}

const _sentinel = Object();

/// 置顶顺序：香港 → 美国 → 新加坡
int _pinPriority(String countryCode) {
  switch (countryCode.toUpperCase()) {
    case 'HK':
      return 0;
    case 'US':
      return 1;
    case 'SG':
      return 2;
    default:
      return 99;
  }
}

List<CountryCard> _initialCountryCards() {
  final staticByCode = <String, Server>{};
  for (final s in smartDolphinStaticServers) {
    staticByCode[s.countryCode.toUpperCase()] = s;
  }
  return allCountries
      .map((e) => CountryCard(
            countryCode: e.$1,
            countryName: e.$2,
            server: staticByCode[e.$1],
            isPinned: e.$1 == 'HK' || e.$1 == 'US' || e.$1 == 'SG',
          ))
      .toList();
}

/// 当 API 返回的卡片少于全部国家时，用初始卡片补齐，确保始终显示全部
List<CountryCard> _mergeWithInitialCards(List<CountryCard> fromApi) {
  final byCode = <String, CountryCard>{};
  for (final c in fromApi) {
    byCode[c.countryCode.toUpperCase()] = c;
  }
  return allCountries
      .map((e) => byCode[e.$1] ?? CountryCard(
            countryCode: e.$1,
            countryName: e.$2,
            server: null,
            isPinned: e.$1 == 'HK' || e.$1 == 'US' || e.$1 == 'SG',
          ))
      .toList();
}

class ServerCatalogController extends StateNotifier<ServerCatalogState> {
  ServerCatalogController(this._ref)
      : super(ServerCatalogState(
          countryCards: _initialCountryCards(),
          isLoading: false,
        )) {
    print('ServerCatalogController constructor called!');
    developer.log(' ServerCatalogController constructor called!', name: 'ServerCatalogController');
    _init();
  }

  final Ref _ref;
  Timer? _latencyTimer;
  bool _measurementInProgress = false;
  bool _latencyPaused = false;
  static const _latencyRefreshInterval = Duration(seconds: 45);
  static const _latencyMeasureConcurrency = 4;

  Future<void> _init() async {
    print('ServerCatalogController._init() called');
    developer.log(' ServerCatalogController._init() called', name: 'ServerCatalogController');
    try {
      developer.log(' Calling ServerRepository.loadCountryCards()', name: 'ServerCatalogController');
      final cards = await _ref.read(serverRepositoryProvider).loadCountryCards();
      print('Received ${cards.length} country cards from repository (expected ${allCountries.length})');
      developer.log(' Received ${cards.length} country cards (expected ${allCountries.length})',
          name: 'ServerCatalogController');

      // 确保始终有全部国家卡片，避免只显示 2 个
      final mergedCards = cards.length >= allCountries.length
          ? cards
          : _mergeWithInitialCards(cards);

      final prefs = _ref.read(serverPreferencesRepositoryProvider);
      final favorites = prefs?.loadFavorites() ?? <String>{};
      state = state.copyWith(
        countryCards: mergedCards,
        favorites: favorites,
        isLoading: false,
      );
      developer.log('✅State updated with ${mergedCards.length} cards', name: 'ServerCatalogController');

      await _measureLatency(fullScan: true);
      _latencyTimer = Timer.periodic(_latencyRefreshInterval, (_) {
        if (_latencyPaused) return;
        unawaited(_measureLatency(fullScan: false));
      });
    } catch (error, stackTrace) {
      print(' ServerCatalogController._init error: $error');
      developer.log('Error in _init()', name: 'ServerCatalogController', error: error, stackTrace: stackTrace);
      state = state.copyWith(
        isLoading: false,
        error: error.toString(),
      );
    }
  }

  void setLatencyPollingPaused(bool paused) {
    _latencyPaused = paused;
  }

  Future<void> _measureLatency({required bool fullScan}) async {
    if (kIsWeb) {
      return;
    }
    final targets = _latencyTargets(fullScan: fullScan);
    if (targets.isEmpty || _measurementInProgress) {
      return;
    }
    _measurementInProgress = true;
    try {
      final results = <String, int>{};
      for (var i = 0; i < targets.length; i += _latencyMeasureConcurrency) {
        final batch = targets.sublist(
          i,
          (i + _latencyMeasureConcurrency).clamp(0, targets.length),
        );
        final entries = await Future.wait(batch.map(_probeServerLatency));
        results.addEntries(entries);
      }
      if (!_latencyChanged(results)) {
        return;
      }
      final updatedCards = state.countryCards.map((c) {
        final measured = c.server != null ? results[c.server!.id] : null;
        if (measured == null) {
          return c;
        }
        return c.copyWith(latencyMs: measured);
      }).toList();
      state = state.copyWith(countryCards: updatedCards, latencyMs: results);
    } finally {
      _measurementInProgress = false;
    }
  }

  List<Server> _latencyTargets({required bool fullScan}) {
    final servers = state.countryCards
        .where((c) => c.server != null && c.server!.endpoint.isNotEmpty)
        .map((c) => c.server!)
        .toList();
    if (fullScan) {
      return servers.toSet().toList();
    }
    final selectedId =
        _ref.read(serverPreferencesRepositoryProvider)?.loadLastServerId();
    final connectedId = state.connectedServerId;
    final pinnedCodes = {'HK', 'US', 'SG'};
    final picked = <String, Server>{};
    for (final server in servers) {
      if (pinnedCodes.contains(server.countryCode.toUpperCase())) {
        picked[server.id] = server;
      }
    }
    if (selectedId != null) {
      final match = servers.where((s) => s.id == selectedId);
      if (match.isNotEmpty) {
        picked[selectedId] = match.first;
      }
    }
    if (connectedId != null) {
      final match = servers.where((s) => s.id == connectedId);
      if (match.isNotEmpty) {
        picked[connectedId] = match.first;
      }
    }
    return picked.values.toList();
  }

  bool _latencyChanged(Map<String, int> next) {
    if (next.isEmpty) {
      return false;
    }
    for (final entry in next.entries) {
      final previous = state.latencyMs[entry.key];
      if (previous == null || (previous - entry.value).abs() > 25) {
        return true;
      }
    }
    return false;
  }

  Future<MapEntry<String, int>> _probeServerLatency(Server server) async {
    try {
      final parts = server.endpoint.split(':');
      final host = parts.first;
      final port = parts.length > 1 ? (int.tryParse(parts[1]) ?? 443) : 1194;
      final stopwatch = Stopwatch()..start();
      final socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 2),
      );
      socket.destroy();
      stopwatch.stop();
      return MapEntry(server.id, stopwatch.elapsedMilliseconds);
    } catch (_) {
      return MapEntry(server.id, 9999);
    }
  }

  void search(String query) {
    state = state.copyWith(query: query);
  }

  void setConnectedServerId(String? id) {
    if (state.connectedServerId == id) return;
    state = state.copyWith(connectedServerId: id);
  }

  Future<void> toggleFavorite(Server server) async {
    final updated = {...state.favorites};
    if (updated.contains(server.id)) {
      updated.remove(server.id);
    } else {
      updated.add(server.id);
    }
    state = state.copyWith(favorites: updated);
    await _ref
        .read(serverPreferencesRepositoryProvider)
        ?.saveFavorites(updated);
  }

  Future<void> clearFavorites() async {
    state = state.copyWith(favorites: <String>{});
    await _ref
        .read(serverPreferencesRepositoryProvider)
        ?.saveFavorites(state.favorites);
  }

  Future<void> rememberSelection(Server server) async {
    await _ref
        .read(serverPreferencesRepositoryProvider)
        ?.saveLastServerId(server.id);
  }

  /// Refresh country cards from API
  Future<void> refreshServers() async {
    developer.log('Refreshing country cards...', name: 'ServerCatalogController');
    state = state.copyWith(isLoading: true, error: null);
    try {
      final cards = await _ref.read(serverRepositoryProvider).loadCountryCards();
      developer.log('Refreshed ${cards.length} country cards', name: 'ServerCatalogController');

      final mergedCards = cards.length >= allCountries.length
          ? cards
          : _mergeWithInitialCards(cards);

      final prefs = _ref.read(serverPreferencesRepositoryProvider);
      final favorites = prefs?.loadFavorites() ?? <String>{};
      state = state.copyWith(
        countryCards: mergedCards,
        favorites: favorites,
        isLoading: false,
      );

      await _measureLatency(fullScan: true);
    } catch (error, stackTrace) {
      print(' ServerCatalogController.refreshServers error: $error');
      developer.log(' Error refreshing', name: 'ServerCatalogController', error: error, stackTrace: stackTrace);
      state = state.copyWith(
        isLoading: false,
        error: error.toString(),
      );
    }
  }

  @override
  void dispose() {
    _latencyTimer?.cancel();
    super.dispose();
  }
}
