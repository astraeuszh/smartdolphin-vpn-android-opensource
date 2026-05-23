import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app.dart';
import '../../../services/storage/prefs.dart';
import '../../../services/vpn/vpn_provider.dart';
import '../../session/domain/session_controller.dart';
import '../../session/domain/session_status.dart';
import '../data/game_decel_tier_repository.dart';
import 'game_decel_tier.dart';
import 'game_mode_overlay_provider.dart';

class GameDecelTierNotifier extends StateNotifier<GameDecelTier> {
  GameDecelTierNotifier(this._ref) : super(GameDecelTier.medium) {
    unawaited(_hydrate());
  }

  final Ref _ref;

  Future<void> _hydrate() async {
    final prefs = await _ref.read(prefsStoreProvider.future);
    final loaded = GameDecelTierRepository(prefs).load();
    state = loaded;
    if (!kIsWeb) {
      _ref.read(openVpnPortProvider).setGameDecelTier(loaded);
    }
  }

  Future<void> setTier(GameDecelTier tier) async {
    state = tier;
    final prefs = await _ref.read(prefsStoreProvider.future);
    await GameDecelTierRepository(prefs).save(tier);
    if (!kIsWeb) {
      _ref.read(openVpnPortProvider).setGameDecelTier(tier);
    }
    await _reconnectTunnelIfNeeded();
  }

  Future<void> _reconnectTunnelIfNeeded() async {
    if (kIsWeb) {
      return;
    }
    if (!_ref.read(gameModeOverlayActiveProvider)) {
      return;
    }
    final session = _ref.read(sessionControllerProvider);
    if (session.status != SessionStatus.connected) {
      return;
    }
    final ctx = _ref.read(navigatorKeyProvider).currentContext;
    if (ctx == null || !ctx.mounted) {
      return;
    }
    await _ref
        .read(sessionControllerProvider.notifier)
        .reconnectToApplyGameModeTunnel(ctx);
  }
}

final gameDecelTierProvider =
    StateNotifierProvider<GameDecelTierNotifier, GameDecelTier>((ref) {
  return GameDecelTierNotifier(ref);
});
