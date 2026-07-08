/// 按设备总内存粗分档，用于 OpenVPN 注入与 UI 降级（非精确跑分）。
enum MemoryTier {
  /// 物理内存不足 2GB 时：更保守的 MTU/缓冲，减轻 CPU/内核压力。
  low,

  /// 2–4GB
  mid,

  /// ≥ 4GB
  high,
}

MemoryTier memoryTierFromTotalRamMb(int? mb) {
  if (mb == null) {
    return MemoryTier.mid;
  }
  if (mb < 2048) {
    return MemoryTier.low;
  }
  if (mb < 4096) {
    return MemoryTier.mid;
  }
  return MemoryTier.high;
}
