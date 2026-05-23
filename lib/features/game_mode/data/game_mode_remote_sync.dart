import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/game_mode_speed.dart';

/// 将来对接真实 HTTP API 时在此实现；当前不发起网络请求。
class GameModeRemoteSync {
  const GameModeRemoteSync._();

  static Future<void> trySync(Ref ref, GameModeSpeed speed) async {
    // TODO: 接入后端后 POST 用户选择的 game_mode（accel/decel）与设备/会话信息
    await Future<void>.delayed(Duration.zero);
  }
}
