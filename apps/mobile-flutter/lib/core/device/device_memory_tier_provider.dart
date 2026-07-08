import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../platform/android/device_memory_channel.dart';
import 'memory_tier.dart';

/// 启动时读一次总内存（MB），用于低端机 OpenVPN/毛玻璃降级。
final deviceMemoryTierProvider = FutureProvider<MemoryTier>((ref) async {
  final mb = await DeviceMemoryChannel.getTotalRamMb();
  return memoryTierFromTotalRamMb(mb);
});
