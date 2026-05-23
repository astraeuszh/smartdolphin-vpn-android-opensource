import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app.dart';
import '../../../services/storage/prefs.dart';
import '../../../services/vpn/vpn_provider.dart';
import '../../session/domain/session_controller.dart';
import '../../session/domain/session_status.dart';
import '../data/game_mode_remote_sync.dart';
import '../data/game_mode_repository.dart';
import 'game_mode_overlay_provider.dart';
import 'game_mode_speed.dart';
import 'game_traffic_providers.dart';

class GameModeController extends StateNotifier<GameModeSpeed> {
  GameModeController(this._ref) : super(GameModeSpeed.accel) {
    unawaited(_hydrate());
  }

  final Ref _ref;

  Future<void> _hydrate() async {
    final prefs = await _ref.read(prefsStoreProvider.future);
    final loaded = GameModeRepository(prefs).load();
    state = loaded;
    if (!kIsWeb) {
      _ref.read(openVpnPortProvider).setGameTrafficMode(loaded);
    }
    await _ref.read(gameTrafficEngineProvider).applyMode(loaded);
  }

  Future<void> setSpeed(GameModeSpeed speed) async {
    state = speed;
    final prefs = await _ref.read(prefsStoreProvider.future);
    await GameModeRepository(prefs).save(speed);
    if (!kIsWeb) {
      _ref.read(openVpnPortProvider).setGameTrafficMode(speed);
    }
    await _ref.read(gameTrafficEngineProvider).applyMode(speed);
    if (!kIsWeb && _ref.read(gameModeOverlayActiveProvider)) {
      await _ref
          .read(gameTrafficEngineProvider)
          .syncGameModeOverlay(visible: true, mode: speed);
    }
    await GameModeRemoteSync.trySync(_ref, speed);
    await _reconnectTunnelIfNeeded();
  }

  Future<void> _reconnectTunnelIfNeeded() async {
    if (kIsWeb) {
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

final gameModeControllerProvider =
    StateNotifierProvider<GameModeController, GameModeSpeed>((ref) {
  return GameModeController(ref);
});
