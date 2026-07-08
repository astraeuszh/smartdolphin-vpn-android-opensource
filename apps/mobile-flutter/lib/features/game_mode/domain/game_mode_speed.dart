/// 游戏模式速度策略（本地持久化 + 后续可同步服务端）
enum GameModeSpeed {
  /// 优先游戏流量 / 低延迟
  accel,

  /// 降低游戏流量占用
  decel,
}

extension GameModeSpeedStorage on GameModeSpeed {
  String toStorage() => name;
}

GameModeSpeed gameModeSpeedFromStorage(String? raw) {
  if (raw == GameModeSpeed.decel.name) {
    return GameModeSpeed.decel;
  }
  return GameModeSpeed.accel;
}
