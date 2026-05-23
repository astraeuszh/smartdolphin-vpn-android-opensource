import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 游戏模式全屏层是否在前台（用于禁用 SmartStable 弹窗等）。
final gameModeOverlayActiveProvider = StateProvider<bool>((ref) => false);
