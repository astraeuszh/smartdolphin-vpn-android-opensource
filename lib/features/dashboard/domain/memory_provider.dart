import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/runtime_platform.dart';
import '../../../platform/android/app_memory_channel.dart';

Future<int?> _readMemoryMb() async {
  if (isAndroidNative) {
    final pss = await AppMemoryChannel.getAppMemoryMb();
    if (pss != null && pss > 0) return pss;
  }
  try {
    final rss = ProcessInfo.currentRss;
    if (rss > 0) return (rss / (1024 * 1024)).round();
  } catch (_) {}
  return null;
}

/// 当前进程内存占用 (MB)，实时刷新
final appMemoryProvider = StreamProvider<int?>((ref) async* {
  yield await _readMemoryMb();
  await for (final _ in Stream.periodic(const Duration(seconds: 2))) {
    yield await _readMemoryMb();
  }
});
