/// 游戏减速档位（仅影响 VPN 隧道内 shaper；展示用延迟区间为大致预期，非保证值）。
enum GameDecelTier {
  /// 轻度：略卡
  low,

  /// 中度：明显顿挫
  medium,

  /// 高度：很慢、不跟手
  high,

  /// 超级：隧道出口极低，基本不可用
  ultra,
}

extension GameDecelTierStorage on GameDecelTier {
  String toStorage() => name;
}

GameDecelTier gameDecelTierFromStorage(String? raw) {
  for (final t in GameDecelTier.values) {
    if (t.name == raw) return t;
  }
  return GameDecelTier.medium;
}

extension GameDecelTierShaper on GameDecelTier {
  /// OpenVPN `shaper`：字节/秒（越小越慢）。档位拉开差距，体感才明显。
  int get shaperBytesPerSecond {
    switch (this) {
      case GameDecelTier.low:
        return 393216; // ~384 KiB/s，略卡
      case GameDecelTier.medium:
        return 40960; // ~40 KiB/s，明显慢
      case GameDecelTier.high:
        return 6144; // ~6 KiB/s，很卡
      case GameDecelTier.ultra:
        return 2048; // ~2 KiB/s，基本不可用（再低易握手异常）
    }
  }
}
