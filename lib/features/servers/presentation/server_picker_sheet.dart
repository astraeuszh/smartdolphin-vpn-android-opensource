import 'dart:async';

import 'package:characters/characters.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_codes.dart';
import '../../../core/errors/error_dialog.dart';
import '../data/country_card.dart';
import '../domain/server_providers.dart';
import '../domain/server_display_name.dart';
import '../../session/domain/session_controller.dart';
import '../../session/domain/session_status.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/haptics/haptics_service.dart';
import '../../../widgets/server_tile.dart';

class ServerPickerSheet extends ConsumerStatefulWidget {
  const ServerPickerSheet({super.key, this.scrollController});

  final ScrollController? scrollController;

  @override
  ConsumerState<ServerPickerSheet> createState() => _ServerPickerSheetState();
}

class _ServerPickerSheetState extends ConsumerState<ServerPickerSheet> {
  late final TextEditingController _searchController;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final q = ref.read(serverCatalogProvider).query;
      if (q.isNotEmpty) {
        _searchController.text = q;
        _query = q.toLowerCase();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    final q = value.trim();
    ref.read(serverCatalogProvider.notifier).search(q);
    setState(() {
      _query = q.toLowerCase();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final catalog = ref.watch(serverCatalogProvider);
    final selectedServer = ref.watch(selectedServerProvider);
    final sessionState = ref.watch(sessionControllerProvider);
    final isConnected = sessionState.status == SessionStatus.connected;
    final cardsAsyncValue = ref.watch(countryCardsAsync);

    ref.listen(sessionControllerProvider, (prev, next) {
      final nextId = next.serverId;
      final prevId = prev?.serverId;
      if (nextId != prevId) {
        ref.read(serverCatalogProvider.notifier).setConnectedServerId(nextId);
      }
    });
    ref.read(serverCatalogProvider.notifier).setConnectedServerId(
          sessionState.serverId,
        );

    final filteredCards = catalog.sortedCountryCards;

    return CustomScrollView(
      controller: widget.scrollController,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child:                 Text(
                    '${l10n.locations} (${catalog.countryCards.length})',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: l10n.connectionQualityRefresh,
                  onPressed: () async {
                    await ref
                        .read(serverCatalogProvider.notifier)
                        .refreshServers();
                    if (!mounted) return;
                    final catalog = ref.read(serverCatalogProvider);
                    if (catalog.error != null &&
                        catalog.error!.trim().isNotEmpty &&
                        catalog.countryCards.length <= 2) {
                      showErrorDialog(
                        context,
                        message: catalog.error!,
                        errorCode: ecNetworkUnstable,
                        title: l10n.locations,
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                labelText: l10n.searchLocations,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                        icon: const Icon(Icons.clear),
                      )
                    : null,
                border: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(16)),
                ),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.showingLocations(filteredCards.length, catalog.countryCards.length),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                      ),
                ),
                if (catalog.error != null && catalog.countryCards.length <= 2) ...[
                  const SizedBox(height: 8),
                  Text(
                    l10n.serverListHintConnectFirst,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.9),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        cardsAsyncValue.when(
          data: (_) {
            if (filteredCards.isEmpty) {
              final message = _query.isEmpty
                  ? l10n.failedToLoadServers
                  : l10n.noLocationsMatch(_searchController.text.trim());
              return SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      message,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              );
            }
            final speedCache = ref.watch(serverSpeedCacheProvider);
            return SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final card = filteredCards[index];
                  final server = card.server;
                  final selected = selectedServer?.id == server?.id;
                  final cache = server != null ? speedCache[server.id] : null;
                  if (server != null) {
                    return Opacity(
                      opacity: card.isConnectable ? 1 : 0.6,
                      child: ServerTile(
                        server: server,
                        selected: selected,
                        latencyMs: card.latencyMs,
                        cachedDownloadMbps: cache?.downloadMbps,
                        cachedUploadMbps: cache?.uploadMbps,
                        onTap: card.isConnectable
                            ? () {
                                unawaited(ref.read(hapticsServiceProvider).selection());
                                if (isConnected) {
                                  if (selected) {
                                    Navigator.of(context).pop();
                                  } else {
                                    Navigator.of(context).pop();
                                    unawaited(ref.read(sessionControllerProvider.notifier)
                                        .switchToServerAndConnect(context: context, server: server));
                                  }
                                } else {
                                  ref.read(selectedServerProvider.notifier).select(server);
                                  Navigator.of(context).pop();
                                }
                              }
                            : null,
                      ),
                    );
                  }
                  return _CountryCardPlaceholder(
                    card: card,
                    onTap: null,
                  );
                },
                childCount: filteredCards.length,
              ),
            );
          },
          loading: () => SliverFillRemaining(
            hasScrollBody: false,
            child: const Center(child: CircularProgressIndicator()),
          ),
          error: (err, stack) => SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text('${l10n.failedToLoadServers}: $err'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CountryCardPlaceholder extends StatelessWidget {
  const _CountryCardPlaceholder({required this.card, this.onTap});

  final CountryCard card;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Opacity(
      opacity: 0.6,
      child: ListTile(
        enabled: false,
        leading: CircleAvatar(
          radius: 22,
          backgroundColor: theme.colorScheme.surfaceVariant.withOpacity(0.5),
          child: Text(
            _flagEmoji(card.countryCode),
            style: const TextStyle(fontSize: 20),
          ),
        ),
        title: Text(card.localizedName(l10n)),
        subtitle: Text(
          card.isLatencyTimeout ? l10n.dashboardTimeout : l10n.serverNoNodes,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withOpacity(0.6),
          ),
        ),
        trailing: Text(
          card.latencyLabel(l10n),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurface.withOpacity(0.6),
          ),
        ),
      ),
    );
  }

  String _flagEmoji(String countryCode) {
    const base = 0x1F1E6;
    return countryCode.toUpperCase().characters.map((char) {
      final codeUnit = char.codeUnitAt(0) - 0x41 + base;
      return String.fromCharCode(codeUnit);
    }).join();
  }
}
