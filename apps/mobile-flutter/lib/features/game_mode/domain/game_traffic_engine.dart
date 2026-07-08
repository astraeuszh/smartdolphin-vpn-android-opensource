import 'game_mode_speed.dart';

/// 游戏模式：**独立于 VPN 隧道** 的本机策略（与正常 VPN 连接无关）。
///
/// 实现侧可为前台服务、系统游戏模式 API、省电策略等；不经购买节点转发流量。
abstract class GameTrafficEngine {
  /// 持久化偏好（加速 / 减速）。
  Future<void> applyMode(GameModeSpeed mode);

  /// 游戏模式全屏打开/关闭时，与原生同步前台服务与系统侧状态。
  Future<void> syncGameModeOverlay({
    required bool visible,
    required GameModeSpeed mode,
  });

  /// 引擎释放（如应用退出）。
  Future<void> stop();
}
