import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/game_mode_speed.dart';
import '../domain/game_traffic_engine.dart';

/// Android：偏好写入 + [syncGameModeOverlay] 时启停本机 [GameModeLocalService]（不经 VPN）。
class LocalGameTrafficEngine implements GameTrafficEngine {
  static const _channel = MethodChannel('astraeus.smartdolphin.vpn/game_traffic');

  @override
  Future<void> applyMode(GameModeSpeed mode) async {
    if (kIsWeb) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('applyMode', mode.name);
    } on PlatformException catch (e, st) {
      debugPrint('[LocalGameTrafficEngine] applyMode failed: $e');
      debugPrintStack(stackTrace: st);
    }
  }

  @override
  Future<void> syncGameModeOverlay({
    required bool visible,
    required GameModeSpeed mode,
  }) async {
    if (kIsWeb) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('syncGameModeOverlay', {
        'visible': visible,
        'mode': mode.name,
      });
    } on PlatformException catch (e, st) {
      debugPrint('[LocalGameTrafficEngine] syncGameModeOverlay failed: $e');
      debugPrintStack(stackTrace: st);
    }
  }

  @override
  Future<void> stop() async {
    if (kIsWeb) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('stop');
    } on PlatformException catch (e, st) {
      debugPrint('[LocalGameTrafficEngine] stop failed: $e');
      debugPrintStack(stackTrace: st);
    }
  }
}
