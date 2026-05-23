import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/country_card.dart';
import '../data/server_preferences_repository.dart';
import 'server.dart';
import 'server_catalog_controller.dart';
import 'server_selection.dart';

final serverSpeedCacheProvider = Provider<Map<String, ServerSpeedCache>>((ref) {
  final repo = ref.watch(serverPreferencesRepositoryProvider);
  return repo?.loadServerSpeedCache() ?? {};
});

final serverCatalogProvider =
    StateNotifierProvider<ServerCatalogController, ServerCatalogState>((ref) {
  return ServerCatalogController(ref);
});

/// Alias retained for legacy imports that still expect [serverCatalogProvider].
final serverCatalogStateProvider = serverCatalogProvider;

/// 可连接 Server 列表（用于连接质量切换等）
final serversProvider = Provider<List<Server>>((ref) {
  final state = ref.watch(serverCatalogProvider);
  return state.connectableServers;
});

/// 国家卡片列表，HK / US / SG 置顶（此顺序），可连接按延迟排序，超时置底
final countryCardsAsync = Provider<AsyncValue<List<CountryCard>>>((ref) {
  final state = ref.watch(serverCatalogProvider);
  if (state.isLoading && state.countryCards.isEmpty) {
    return const AsyncValue.loading();
  }
  if (state.sortedCountryCards.isNotEmpty) {
    return AsyncValue.data(state.sortedCountryCards);
  }
  if (state.error != null) {
    return AsyncValue.error(state.error!, StackTrace.current);
  }
  return AsyncValue.data(state.sortedCountryCards);
});

/// Legacy: 兼容需要 List<Server> 的 UI，返回可连接节点的 Server 列表
final serversAsync = Provider<AsyncValue<List<Server>>>((ref) {
  return ref.watch(countryCardsAsync).when(
        data: (cards) => AsyncValue.data(
          cards
              .where((c) => c.isConnectable && c.server != null)
              .map((c) => c.server!)
              .toList(),
        ),
        loading: () => const AsyncValue.loading(),
        error: (e, st) => AsyncValue.error(e, st),
      );
});

final selectedServerProvider =
    StateNotifierProvider<ServerSelectionNotifier, Server?>((ref) {
  return ServerSelectionNotifier(ref, serverCatalogProvider);
});

final serverLatencyProvider = Provider<Map<String, int>>((ref) {
  return ref.watch(serverCatalogProvider).latencyMs;
});
