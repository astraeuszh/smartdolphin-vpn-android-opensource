import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

int? _readMemoryMb() {
  try {
    final rss = ProcessInfo.currentRss;
    if (rss > 0) return (rss / (1024 * 1024)).round();
  } catch (_) {}
  return null;
}

/// 当前进程内存占用 (MB)，实时刷新
final appMemoryProvider = StreamProvider<int?>((ref) async* {
  yield _readMemoryMb();
  await for (final _ in Stream.periodic(const Duration(seconds: 1))) {
    yield _readMemoryMb();
  }
});
