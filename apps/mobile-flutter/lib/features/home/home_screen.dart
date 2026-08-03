import 'dart:async';
import 'dart:convert';
import 'dart:io' show exit;
import 'dart:ui';

import 'package:characters/characters.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/haptics/haptics_service.dart';
import '../../../core/device/device_memory_tier_provider.dart';
import '../../../core/device/memory_tier.dart';
import '../../../core/ui/top_snack.dart';
import '../../../core/errors/error_codes.dart';
import '../../../core/errors/error_dialog.dart';
import '../../theme/colors.dart';
import '../../widgets/connect_control.dart';
import '../../widgets/frosted_glass.dart';
import '../../l10n/app_localizations.dart';
import '../dashboard/domain/ip_info_provider.dart';
import '../../../l10n/country_names.dart';
import '../home/domain/home_local_stats_provider.dart';
import '../home/domain/home_packet_loss_provider.dart';
import '../dashboard/presentation/dashboard_screen.dart';
import '../servers/data/country_card.dart';
import '../servers/domain/server.dart';
import '../connection/domain/tunnel_throughput_provider.dart';
import '../servers/data/server_preferences_repository.dart';
import '../servers/domain/server_providers.dart';
import '../servers/domain/server_display_name.dart';
import '../servers/presentation/server_picker_sheet.dart';
import '../auth/domain/auth_controller.dart';
import '../auth/presentation/qr_scan_screen.dart';
import '../session/domain/session_controller.dart';
import '../../services/remote/console_feedback.dart';
import '../../services/vpn/vpn_provider.dart';
import '../session/domain/session_state.dart';
import '../session/domain/session_status.dart';
import '../session/presentation/countdown.dart';
import '../speedtest/presentation/speedtest_screen.dart';
import '../settings/presentation/settings_screen.dart';
import '../../services/notifications/session_notification_service.dart';
import '../../services/remote/console_announcements.dart';
import '../../services/storage/prefs.dart';
import '../usage/data_usage_controller.dart';
import '../usage/data_usage_state.dart';
import '../game_mode/domain/game_mode_controller.dart';
import '../game_mode/domain/game_mode_overlay_provider.dart';
import '../game_mode/domain/game_mode_speed.dart';
import '../game_mode/domain/game_traffic_providers.dart';
import '../game_mode/presentation/game_mode_screen.dart';
import '../../../platform/android/background_keep_alive.dart';
import '../connection/domain/connection_quality_controller.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

const _actionDebounceMs = 600;
const _dismissedAnnouncementsKey = 'announcements.dismissed_ids';
const _dismissedAnnouncementVersionsKey = 'announcements.dismissed_versions';
const _lastSeenAnnouncementKey = 'announcements.last_seen_updated_at';

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  final GlobalKey _serverCarouselKey = GlobalKey();
  final GlobalKey _connectKey = GlobalKey();
  final GlobalKey _statusKey = GlobalKey();
  final GlobalKey _speedTabKey = GlobalKey();
  int _tabIndex = 0;
  bool _navDragging = false;
  double? _navIndicatorLeft;

  /// 游戏模式全屏：底栏收起，入口为小球。
  bool _gameModeExpanded = false;
  bool _connectTapInFlight = false;
  bool _didSchedulePostFrameCallback = false;
  DateTime? _lastConnectTap;
  DateTime? _lastSwitchTap;
  Timer? _policyRefreshTimer;
  bool _showingAnnouncement = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _policyRefreshTimer = Timer.periodic(const Duration(minutes: 30), (_) {
      if (!mounted) return;
      unawaited(_maybeShowAnnouncement());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final paused = state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached;
    ref.read(serverCatalogProvider.notifier).setLatencyPollingPaused(paused);
    // 应用进入后台时停掉账户/公告轮询，避免长时间挂起后定时器堆积导致卡死。
    if (paused) {
      _policyRefreshTimer?.cancel();
      _policyRefreshTimer = null;
    }
    if (state == AppLifecycleState.resumed) {
      _policyRefreshTimer ??= Timer.periodic(const Duration(minutes: 30), (_) {
        if (!mounted) return;
        unawaited(_maybeShowAnnouncement());
      });
      // 长时间后台后 Flutter semantics 树可能卡住；预热一帧并延迟刷新账户状态。
      WidgetsBinding.instance.scheduleWarmUpFrame();
      Future<void>.delayed(const Duration(milliseconds: 400), () {
        if (!mounted) return;
        unawaited(ref.read(authControllerProvider.notifier).refreshSession());
        unawaited(_maybeShowAnnouncement());
        // 息屏/后台数小时后隧道可能已死；恢复前台时探测 Clash API 并按需硬重连。
        unawaited(ref
            .read(sessionControllerProvider.notifier)
            .checkTunnelHealthOnResume());
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didSchedulePostFrameCallback) {
      return;
    }
    _didSchedulePostFrameCallback = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_handleAppLaunchFlow());
    });
  }

  @override
  void dispose() {
    _policyRefreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _safeDisconnect(WidgetRef ref) async {
    try {
      await ref.read(sessionControllerProvider.notifier).disconnect();
    } catch (e, st) {
      debugPrint('[HomeScreen] disconnect error: $e');
      debugPrintStack(stackTrace: st);
    }
  }

  Future<void> _handleAppLaunchFlow() async {
    if (!mounted) return;
    // 启动后请求一次通知权限：用于断网保护、连接状态、TileService 等。
    unawaited(ref.read(sessionNotificationServiceProvider).requestPermission());
    // 重传离线期间排队的反馈/工单。
    unawaited(ConsoleFeedback().flushPending());
    unawaited(_maybeShowAnnouncement());
    final auth = ref.read(authControllerProvider);
    if (auth.status == AuthStatus.authenticated &&
        auth.session?.canUseVpn == true) {
      final fromBoot = await consumeLaunchFromBoot();
      unawaited(
        ref.read(sessionControllerProvider.notifier).autoConnectIfEnabled(
              context: context,
              fromBoot: fromBoot,
            ),
      );
    }
    Future<void>.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      unawaited(_warmUpVpn());
    });
  }

  Future<Map<int, int>> _loadDismissedAnnouncementVersions(
      PrefsStore prefs) async {
    final raw = prefs.getString(_dismissedAnnouncementVersionsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        return {
          for (final e in map.entries)
            if (int.tryParse(e.key) != null &&
                int.tryParse('${e.value}') != null)
              int.parse(e.key): int.parse('${e.value}'),
        };
      } catch (_) {}
    }
    final legacy = await _loadDismissedAnnouncementIds(prefs);
    if (legacy.isEmpty) return {};
    return {for (final id in legacy) id: 0};
  }

  Future<Set<int>> _loadDismissedAnnouncementIds(PrefsStore prefs) async {
    final raw = prefs.getString(_dismissedAnnouncementsKey);
    if (raw == null || raw.isEmpty) {
      return {};
    }
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => int.tryParse('$e') ?? 0)
          .where((id) => id > 0)
          .toSet();
    } catch (_) {
      return {};
    }
  }

  Future<void> _dismissAnnouncement(ConsoleAnnouncement announcement) async {
    final prefs = await ref.read(prefsStoreProvider.future);
    final dismissed = await _loadDismissedAnnouncementVersions(prefs);
    dismissed[announcement.id] = announcement.updatedAt;
    await prefs.setString(
      _dismissedAnnouncementVersionsKey,
      jsonEncode(dismissed.map((k, v) => MapEntry('$k', v))),
    );
    final legacy = await _loadDismissedAnnouncementIds(prefs);
    legacy.add(announcement.id);
    await prefs.setString(
      _dismissedAnnouncementsKey,
      jsonEncode(legacy.toList()),
    );
  }

  bool _announcementSeen(
    ConsoleAnnouncement row,
    Map<int, int> dismissedVersions,
  ) {
    final seenAt = dismissedVersions[row.id];
    if (seenAt == null) return false;
    return seenAt >= row.updatedAt;
  }

  Future<void> _maybeShowAnnouncement() async {
    if (!mounted || _showingAnnouncement) return;
    try {
      final rows = await ConsoleAnnouncements().fetchPublished();
      if (rows.isEmpty || !mounted) return;

      final prefs = await ref.read(prefsStoreProvider.future);
      final dismissed = await _loadDismissedAnnouncementVersions(prefs);
      final unseen = rows
          .where((row) => !_announcementSeen(row, dismissed))
          .toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      if (unseen.isEmpty || !mounted) return;

      final announcement = unseen.first;
      _showingAnnouncement = true;
      final acknowledged = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text(announcement.title),
          content: SingleChildScrollView(
            child: Text(announcement.body),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(context.l10n.homeAnnouncementAck),
            ),
          ],
        ),
      );
      _showingAnnouncement = false;
      if (acknowledged == true && mounted) {
        await _dismissAnnouncement(announcement);
        await prefs.setString(
          _lastSeenAnnouncementKey,
          '${announcement.updatedAt}',
        );
        if (mounted) {
          unawaited(_maybeShowAnnouncement());
        }
      }
    } catch (e, st) {
      _showingAnnouncement = false;
      debugPrint('[HomeScreen] announcement error: $e');
      debugPrintStack(stackTrace: st);
    }
  }

  Future<void> _warmUpVpn() async {
    try {
      final port = ref.read(openVpnPortProvider);
      await port.prepare();
    } catch (_) {}
  }

  void _setGameModeExpanded(bool v) {
    ref.read(gameModeOverlayActiveProvider.notifier).state = v;
    setState(() => _gameModeExpanded = v);
    if (!kIsWeb) {
      ref.read(openVpnPortProvider).setGameModeOverlayActive(v);
      unawaited(_syncGameModeLocalOverlay(v));
      if (v) {
        final connected = ref.read(sessionControllerProvider).status ==
            SessionStatus.connected;
        if (connected) {
          unawaited(_safeDisconnect(ref));
        }
      }
    }
  }

  Future<void> _syncGameModeLocalOverlay(bool visible) async {
    final mode = ref.read(gameModeControllerProvider);
    await ref.read(gameTrafficEngineProvider).syncGameModeOverlay(
          visible: visible,
          mode: mode,
        );
  }

  double _serverCardWidth(double maxWidth) {
    final proposed = maxWidth * 0.68;
    if (proposed < 220) {
      return 220;
    }
    if (proposed > 320) {
      return 320;
    }
    return proposed;
  }

  double _estimateCountryCardHeight(BoxConstraints constraints) {
    // Leave headroom for two-line titles + metrics row (avoids bottom overflow on web/desktop).
    var height = 232.0;
    if (constraints.maxWidth < 360) {
      height += 28;
    } else if (constraints.maxWidth < 420) {
      height += 12;
    }
    return height.clamp(232.0, 292.0).toDouble();
  }

  bool _serverHasDistinctIpLine(Server server) {
    final host = server.hostName?.trim();
    final ip = (server.ip ?? server.endpoint.split(':').first).trim();
    if (host == null || host.isEmpty) {
      return false;
    }
    if (ip.isEmpty) {
      return false;
    }
    return host != ip;
  }

  void _onSessionChanged(SessionState? previous, SessionState next) {
    if (!mounted) return;
    if (previous?.status != SessionStatus.error &&
        next.status == SessionStatus.error &&
        next.errorMessage != null) {
      final code = next.errorCode ?? 0x00030100;
      final timerExit = code == ecSessionTimerCap;
      final l10n = AppLocalizations.of(context);
      unawaited(showErrorDialog(
        context,
        message: next.errorMessage!,
        errorCode: code,
        title: timerExit ? l10n.homeNoticeTitle : l10n.statusError,
        onClose: timerExit
            ? () {
                if (!kIsWeb) {
                  exit(0);
                }
              }
            : null,
      ));
    }
  }

  void _onDataUsageChanged(DataUsageState? previous, DataUsageState next) {
    if (!mounted) return;
    if (next.pendingTraffic90Dialog &&
        !(previous?.pendingTraffic90Dialog ?? false)) {
      final l10n = AppLocalizations.of(context);
      unawaited(
        showErrorDialog(
          context,
          message: l10n.homeTrafficUsageLowMessage,
          errorCode: ecTrafficQuota90,
          title: l10n.homeTrafficUsageTitle,
          onClose: () {
            unawaited(
              ref
                  .read(dataUsageControllerProvider.notifier)
                  .clearTraffic90Dialog(),
            );
          },
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<SessionState>(sessionControllerProvider, _onSessionChanged);
    ref.listen<DataUsageState>(
        dataUsageControllerProvider, _onDataUsageChanged);
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final sessionState = ref.watch(sessionControllerProvider);
    if (sessionState.status == SessionStatus.connected) {
      ref.watch(connectionQualityControllerProvider);
    }
    final blurSigma = ref.watch(deviceMemoryTierProvider).when(
          data: (t) => t == MemoryTier.low ? 0.0 : HiVpnGlass.blurSigmaNav,
          loading: () => HiVpnGlass.blurSigmaNav,
          error: (_, __) => HiVpnGlass.blurSigmaNav,
        );
    return Scaffold(
      extendBody: true,
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 420),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: _gameModeExpanded
                ? GameModeScreen(
                    key: const ValueKey<String>('game_mode'),
                    onExit: () {
                      unawaited(ref.read(hapticsServiceProvider).selection());
                      _setGameModeExpanded(false);
                    },
                  )
                : SafeArea(
                    key: const ValueKey<String>('main_shell'),
                    top: true,
                    bottom: false,
                    child: _buildMainTab(context, l10n),
                  ),
          ),
          if (!_gameModeExpanded)
            Positioned(
              left: 18,
              right: 18,
              bottom: 10 + MediaQuery.paddingOf(context).bottom,
              child: _buildMainBottomBar(theme, l10n, blurSigma: blurSigma),
            ),
        ],
      ),
    );
  }

  Widget _buildMainTab(BuildContext context, AppLocalizations l10n) {
    return switch (_tabIndex) {
      0 => _buildHomeTab(context, l10n),
      1 => const SpeedTestScreen(),
      2 => const DashboardScreen(),
      3 => const SettingsScreen(),
      _ => _buildHomeTab(context, l10n),
    };
  }

  /// 常规四键 + 中间游戏 — 内凹银底栏；选中项水滴指示器可长按/滑动切换。
  Widget _buildMainBottomBar(
    ThemeData theme,
    AppLocalizations l10n, {
    required double blurSigma,
  }) {
    return LiquidGlass(
      borderRadius: BorderRadius.circular(999),
      blurSigma: blurSigma,
      liveBlur: true,
      child: SizedBox(
        height: 68,
        child: LayoutBuilder(
          builder: (context, constraints) {
            const hPad = 8.0;
            const gameGap = 54.0;
            final barWidth = constraints.maxWidth;
            final slotWidth = (barWidth - hPad * 2 - gameGap) / 4;

            double indicatorLeft(int index) {
              if (index <= 1) {
                return hPad + index * slotWidth;
              }
              return hPad + index * slotWidth + gameGap;
            }

            int tabFromX(double x) {
              final adjusted = (x - hPad).clamp(0.0, barWidth - hPad * 2);
              if (adjusted < slotWidth) return 0;
              if (adjusted < slotWidth * 2) return 1;
              if (adjusted < slotWidth * 2 + gameGap) {
                return adjusted < slotWidth * 2 + gameGap / 2 ? 1 : 2;
              }
              if (adjusted < slotWidth * 3 + gameGap) return 2;
              return 3;
            }

            final pillWidth = slotWidth - 8;
            final pillLeft =
                _navIndicatorLeft ?? (indicatorLeft(_tabIndex) + 4);

            void beginNavDrag() {
              setState(() {
                _navDragging = true;
                _navIndicatorLeft ??= indicatorLeft(_tabIndex) + 4;
              });
            }

            void updateNavDrag(double x) {
              final minLeft = hPad + 4;
              final maxLeft = barWidth - hPad - pillWidth - 4;
              final targetLeft = (x - pillWidth / 2).clamp(minLeft, maxLeft);
              setState(() {
                _navDragging = true;
                _navIndicatorLeft = targetLeft;
              });
            }

            void endNavDrag(double x) {
              final tab = tabFromX(x);
              if (tab != _tabIndex) {
                unawaited(ref.read(hapticsServiceProvider).selection());
              }
              setState(() {
                _navDragging = false;
                _navIndicatorLeft = null;
                _tabIndex = tab;
              });
            }

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onLongPressStart: (_) {
                unawaited(ref.read(hapticsServiceProvider).selection());
                beginNavDrag();
              },
              onLongPressMoveUpdate: (details) =>
                  updateNavDrag(details.localPosition.dx),
              onLongPressEnd: (details) => endNavDrag(details.localPosition.dx),
              onLongPressCancel: () => setState(() {
                _navDragging = false;
                _navIndicatorLeft = null;
              }),
              onHorizontalDragStart: (details) {
                unawaited(ref.read(hapticsServiceProvider).selection());
                beginNavDrag();
                updateNavDrag(details.localPosition.dx);
              },
              onHorizontalDragUpdate: (details) =>
                  updateNavDrag(details.localPosition.dx),
              onHorizontalDragEnd: (details) =>
                  endNavDrag(details.localPosition.dx),
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  AnimatedPositioned(
                    duration: Duration(milliseconds: _navDragging ? 0 : 620),
                    curve: Curves.elasticOut,
                    left: pillLeft,
                    top: 10,
                    width: pillWidth,
                    height: 48,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white.withValues(alpha: 0.98),
                            const Color(0xFFEAF3FF).withValues(alpha: 0.78),
                          ],
                        ),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.98),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: theme.colorScheme.primary
                                .withValues(alpha: 0.2),
                            blurRadius: 24,
                            offset: const Offset(0, 10),
                            spreadRadius: -10,
                          ),
                          BoxShadow(
                            color: Colors.white.withValues(alpha: 0.86),
                            blurRadius: 12,
                            offset: const Offset(-3, -4),
                            spreadRadius: -7,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: hPad),
                    child: Row(
                      children: [
                        Expanded(
                          child: _bottomNavIcon(
                            0,
                            Icons.home_outlined,
                            Icons.home_rounded,
                            l10n.navHome,
                          ),
                        ),
                        Expanded(
                          child: _bottomNavIcon(
                            1,
                            Icons.speed_outlined,
                            Icons.speed,
                            l10n.navSpeedTest,
                            buttonKey: _speedTabKey,
                          ),
                        ),
                        const SizedBox(width: gameGap),
                        Expanded(
                          child: _bottomNavIcon(
                            2,
                            Icons.dashboard_outlined,
                            Icons.dashboard,
                            l10n.navDashboard,
                          ),
                        ),
                        Expanded(
                          child: _bottomNavIcon(
                            3,
                            Icons.settings_outlined,
                            Icons.settings,
                            l10n.navSettings,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    top: 8,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () {
                          unawaited(ref.read(hapticsServiceProvider).impact());
                          _setGameModeExpanded(true);
                        },
                        child: LiquidGlass(
                          borderRadius: BorderRadius.circular(999),
                          blurSigma: blurSigma,
                          liveBlur: false,
                          padding: const EdgeInsets.all(10),
                          child: Icon(
                            Icons.sports_esports_rounded,
                            color: theme.colorScheme.primary,
                            size: 25,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _bottomNavIcon(
    int index,
    IconData outline,
    IconData filled,
    String tooltip, {
    Key? buttonKey,
  }) {
    final selected = _tabIndex == index;
    final cs = Theme.of(context).colorScheme;
    return IconButton(
      key: buttonKey,
      tooltip: tooltip,
      onPressed: () {
        if (index == _tabIndex) return;
        unawaited(ref.read(hapticsServiceProvider).selection());
        setState(() {
          _tabIndex = index;
          _navIndicatorLeft = null;
        });
      },
      icon: Icon(selected ? filled : outline, size: 26),
      color:
          selected ? cs.primary : cs.onSurfaceVariant.withValues(alpha: 0.88),
    );
  }

  Widget _buildHomeTab(BuildContext context, AppLocalizations l10n) {
    final session = ref.watch(sessionControllerProvider);
    final auth = ref.watch(authControllerProvider);
    final selectedServer = ref.watch(selectedServerProvider);
    final liveThroughput = ref.watch(tunnelThroughputProvider);
    final speedCache = ref.watch(serverSpeedCacheProvider);
    final theme = Theme.of(context);
    final titleBaseStyle =
        theme.textTheme.headlineSmall ?? const TextStyle(fontSize: 24);
    final titleStyle = titleBaseStyle.copyWith(fontWeight: FontWeight.w700);

    final isPreparing = session.status == SessionStatus.preparing;
    final isConnecting = session.status == SessionStatus.connecting;
    final isAttemptCancelable = isPreparing || isConnecting;
    final isBusy = isAttemptCancelable;
    final isConnected = session.status == SessionStatus.connected;
    final bottomNavReserve = 88.0 + MediaQuery.paddingOf(context).bottom;
    final buttonState = isConnected
        ? ConnectButtonVisualState.active
        : isAttemptCancelable || _connectTapInFlight
            ? session.connectionWarning
                ? ConnectButtonVisualState.warning
                : ConnectButtonVisualState.connecting
            : session.status == SessionStatus.error
                ? ConnectButtonVisualState.error
                : ConnectButtonVisualState.idle;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: 'SmartDolphin',
                            style: titleStyle.copyWith(
                              color: theme.colorScheme.onSurface,
                              fontSize: 22,
                            ),
                          ),
                          TextSpan(
                            text: 'VPN',
                            style: titleStyle.copyWith(
                              color: theme.colorScheme.primary,
                              fontSize: 22,
                            ),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 10),
                  KeyedSubtree(
                    key: _statusKey,
                    child: IconButton(
                      tooltip: l10n.authQrScanTitle,
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.qr_code_scanner, size: 22),
                      onPressed: auth.status == AuthStatus.authenticated ||
                              auth.status == AuthStatus.pending
                          ? () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const QrScanScreen(),
                                ),
                              );
                            }
                          : null,
                    ),
                  ),
                ],
              ),
              if (session.status == SessionStatus.error &&
                  session.errorMessage != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline,
                          color: theme.colorScheme.error, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          session.errorMessage!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: bottomNavReserve),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 23),
                GestureDetector(
                  onTap: () => unawaited(_showServerPicker(context)),
                  child: LiquidGlass(
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    borderRadius: BorderRadius.circular(22),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 14),
                    child: Row(
                      children: [
                        if (selectedServer != null)
                          Text(
                            _flagEmoji(selectedServer.countryCode),
                            style: const TextStyle(fontSize: 26),
                          ),
                        if (selectedServer != null) const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                selectedServer?.name ??
                                    l10n.selectServerToBegin,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                selectedServer != null
                                    ? selectedServer.countryCode.toUpperCase()
                                    : l10n.noServerSelected,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.62),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.45),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        KeyedSubtree(
                          key: _connectKey,
                          child: ConnectControl(
                            enabled: !_connectTapInFlight &&
                                (!isBusy || isAttemptCancelable),
                            isActive: isConnected,
                            isLoading: isBusy || _connectTapInFlight,
                            visualState: buttonState,
                            label: isConnected
                                ? l10n.disconnect
                                : isAttemptCancelable
                                    ? l10n.statusConnecting
                                    : l10n.connect,
                            statusText:
                                isAttemptCancelable ? l10n.tapToCancel : null,
                            onTap: () async {
                              if (_connectTapInFlight) return;
                              _connectTapInFlight = true;
                              if (mounted) setState(() {});
                              await ref.read(hapticsServiceProvider).impact();
                              try {
                                if (isConnected || isAttemptCancelable) {
                                  await _safeDisconnect(ref);
                                } else {
                                  final server = selectedServer;
                                  if (server == null) {
                                    showTopSnackBar(
                                        context, l10n.pleaseSelectServer);
                                    return;
                                  }
                                  final ok = await ref
                                      .read(authControllerProvider.notifier)
                                      .ensureVpnAccess();
                                  if (!ok) {
                                    final currentAuth =
                                        ref.read(authControllerProvider);
                                    if (currentAuth.session != null &&
                                        currentAuth.session?.banned != true) {
                                      await ref
                                          .read(sessionControllerProvider
                                              .notifier)
                                          .connect(
                                            context: context,
                                            server: server,
                                          );
                                      return;
                                    }
                                    final msg = currentAuth.message ??
                                        l10n.homeLoginVpnRequired;
                                    if (context.mounted) {
                                      showTopSnackBar(context, msg,
                                          isError: true);
                                    }
                                    return;
                                  }
                                  await ref
                                      .read(sessionControllerProvider.notifier)
                                      .connect(
                                          context: context, server: server);
                                }
                              } finally {
                                _connectTapInFlight = false;
                                if (mounted) setState(() {});
                              }
                            },
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (isConnected)
                          const SessionCountdown()
                        else
                          Text(
                            l10n.unlockSecureAccess,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.52),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                _HomeConnectionStats(
                  l10n: l10n,
                  server: selectedServer,
                  isConnected: isConnected,
                  publicIp: session.publicIp,
                  liveThroughput: liveThroughput,
                  speedCache: speedCache,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _statusBadgeLabel(SessionStatus status, AppLocalizations l10n) {
    switch (status) {
      case SessionStatus.connected:
        return l10n.statusConnected;
      case SessionStatus.connecting:
        return l10n.statusConnecting;
      case SessionStatus.preparing:
        return l10n.statusPreparing;
      case SessionStatus.error:
        return l10n.statusError;
      case SessionStatus.disconnected:
      default:
        return l10n.statusDisconnected;
    }
  }

  Color _statusDotColor(SessionStatus status) {
    switch (status) {
      case SessionStatus.connected:
        return HiVpnColors.success;
      case SessionStatus.connecting:
      case SessionStatus.preparing:
        return HiVpnColors.warning;
      case SessionStatus.error:
        return HiVpnColors.error;
      case SessionStatus.disconnected:
      default:
        return HiVpnColors.error;
    }
  }

  Future<void> _showServerPicker(BuildContext context) async {
    await ref.read(hapticsServiceProvider).selection();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => HiVpnSheetScaffold(
        child: DraggableScrollableSheet(
          initialChildSize: 0.55,
          minChildSize: 0.35,
          maxChildSize: 0.92,
          expand: false,
          builder: (_, scrollController) => ServerPickerSheet(
            scrollController: scrollController,
          ),
        ),
      ),
    );
  }

  String _flagEmoji(String countryCode) {
    final base = 0x1F1E6;
    return countryCode.toUpperCase().characters.map((char) {
      final codeUnit = char.codeUnitAt(0) - 0x41 + base;
      return String.fromCharCode(codeUnit);
    }).join();
  }
}

class _HomeConnectionStats extends ConsumerWidget {
  const _HomeConnectionStats({
    required this.l10n,
    required this.server,
    required this.isConnected,
    required this.publicIp,
    required this.liveThroughput,
    required this.speedCache,
  });

  final AppLocalizations l10n;
  final Server? server;
  final bool isConnected;
  final String? publicIp;
  final TunnelThroughputState liveThroughput;
  final Map<String, ServerSpeedCache> speedCache;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final localStats = !isConnected
        ? ref.watch(homeLocalStatsPeriodicProvider).valueOrNull
        : null;
    final packetLoss = ref.watch(homePacketLossProvider).valueOrNull;
    final systemLatency = ref.watch(homeSystemLatencyProvider).valueOrNull;
    final ipInfo = ref.watch(ipInfoProvider).valueOrNull;
    final cached = server != null ? speedCache[server!.id] : null;
    String downloadText = '--';
    String uploadText = '--';
    String _fmtMbps(double? v) {
      if (v == null) return '--';
      if (v < 0.01) return '0.0 Mbps';
      return '${v.toStringAsFixed(1)} Mbps';
    }

    if (isConnected) {
      // These two cards describe the selected route's tested/capacity speed.
      // Instantaneous tunnel traffic naturally sits around 0.x while idle and
      // belongs on the live dashboard chart, not in the route speed cards.
      if (cached != null) {
        downloadText = '${cached.downloadMbps.toStringAsFixed(1)} Mbps';
        uploadText = '${cached.uploadMbps.toStringAsFixed(1)} Mbps';
      } else if (server != null) {
        downloadText =
            _formatBandwidth(server!.downloadSpeed ?? server!.bandwidth);
        uploadText = _formatBandwidth(server!.uploadSpeed ?? server!.bandwidth);
      } else {
        downloadText = _fmtMbps(liveThroughput.downloadMbps);
        uploadText = _fmtMbps(liveThroughput.uploadMbps);
      }
    } else if (localStats != null) {
      if (localStats.downloadMbps != null && localStats.downloadMbps! > 0) {
        downloadText = '${localStats.downloadMbps!.toStringAsFixed(1)} Mbps';
      }
      if (localStats.uploadMbps != null && localStats.uploadMbps! > 0) {
        uploadText = '${localStats.uploadMbps!.toStringAsFixed(1)} Mbps';
      }
    }

    final packetLossText =
        packetLoss != null ? '${packetLoss.toStringAsFixed(1)}%' : '--';

    final ipText =
        (isConnected ? publicIp : null) ?? localStats?.ip ?? ipInfo?.ip ?? '--';

    final latencyMs = systemLatency;
    final latencyText =
        latencyMs != null && latencyMs > 0 ? '$latencyMs ms' : '--';
    final liveUploadLabel =
        l10n.locale.languageCode == 'zh' ? '实时上传' : 'Live upload';
    final liveDownloadLabel =
        l10n.locale.languageCode == 'zh' ? '实时下载' : 'Live download';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _HomeStatCard(
                  label: isConnected ? liveUploadLabel : l10n.serverUploadLabel,
                  value: uploadText,
                  theme: theme,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _HomeStatCard(
                  label: isConnected
                      ? liveDownloadLabel
                      : l10n.serverDownloadLabel,
                  value: downloadText,
                  theme: theme,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LiquidGlass(
            borderRadius: BorderRadius.circular(24),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: _HomeInfoCell(
                    label: l10n.speedTestIpLabel,
                    value: ipText,
                    theme: theme,
                    singleLine: true,
                  ),
                ),
                _infoDivider(),
                Expanded(
                  child: _HomeInfoCell(
                    label: l10n.latencyLabel,
                    value: latencyText,
                    theme: theme,
                  ),
                ),
                _infoDivider(),
                Expanded(
                  child: _HomeInfoCell(
                    label: l10n.packetLossLabel,
                    value: packetLossText,
                    theme: theme,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _physicalAddress(
    AppLocalizations l10n,
    Server? server,
    IpInfo? ipInfo,
    bool isConnected,
    HomeLocalStats? localStats,
  ) {
    if (isConnected && server != null) {
      return englishServerAddress(server);
    }
    final cc =
        (localStats?.countryCode ?? ipInfo?.countryCode ?? '').toUpperCase();
    if (_isCnLike(cc)) {
      return formatIpDisplayLocation(
        countryCode: cc,
        region: localStats?.region ?? ipInfo?.region,
        city: localStats?.city ?? ipInfo?.city,
        org: ipInfo?.org,
        isp: ipInfo?.isp,
        country: ipInfo?.country,
        languageTag: 'en',
      );
    }
    final city = localStats?.city ?? ipInfo?.city;
    if (city != null && city.isNotEmpty) return city;
    final region = localStats?.region ?? ipInfo?.region;
    if (region != null && region.isNotEmpty) return region;
    if (cc.isNotEmpty) {
      return kCountryNamesEn[cc] ?? cc;
    }
    return ipInfo?.country ?? localStats?.region ?? '--';
  }

  static bool _isCnLike(String code) =>
      code == 'CN' || code == 'HK' || code == 'TW' || code == 'MO';

  /// 把「河北省」「内蒙古自治区」「新疆维吾尔自治区」等正式省名压缩为短名。
  static String? _cnShortRegion(String? raw) {
    if (raw == null) return null;
    var name = raw.trim();
    if (name.isEmpty) return null;
    // 英文回名：Hebei → 河北 等不在此处转换；优先返回原文
    const stripSuffixes = [
      '维吾尔自治区',
      '回族自治区',
      '壮族自治区',
      '自治区',
      '特别行政区',
      'Province',
      'province',
      ' Province',
    ];
    for (final s in stripSuffixes) {
      if (name.endsWith(s)) {
        name = name.substring(0, name.length - s.length).trim();
        break;
      }
    }
    if (name.endsWith('省') || name.endsWith('市')) {
      name = name.substring(0, name.length - 1);
    }
    return name.isEmpty ? null : name;
  }

  Widget _infoDivider() {
    return Container(
      width: 1,
      height: 36,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: Colors.white.withValues(alpha: 0.35),
    );
  }

  String _formatBandwidth(num? value) {
    if (value == null || value <= 0) return '--';
    const units = ['bps', 'Kbps', 'Mbps', 'Gbps'];
    var display = value.toDouble();
    var unitIndex = 2;
    if (display < 1) {
      while (display < 1 && unitIndex > 0) {
        display *= 1000;
        unitIndex--;
      }
    } else if (display >= 1000) {
      while (display >= 1000 && unitIndex < units.length - 1) {
        display /= 1000;
        unitIndex++;
      }
    }
    return '${display.toStringAsFixed(1)} ${units[unitIndex]}';
  }
}

class _HomeStatCard extends StatelessWidget {
  const _HomeStatCard({
    required this.label,
    required this.value,
    required this.theme,
  });

  final String label;
  final String value;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return LiquidGlass(
      borderRadius: BorderRadius.circular(20),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.52),
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _HomeInfoCell extends StatelessWidget {
  const _HomeInfoCell({
    required this.label,
    required this.value,
    required this.theme,
    this.singleLine = false,
  });

  final String label;
  final String value;
  final ThemeData theme;
  final bool singleLine;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.52),
            fontWeight: FontWeight.w600,
            fontSize: 10,
          ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: singleLine ? 10 : 12,
            fontFeatures:
                singleLine ? const [FontFeature.tabularFigures()] : null,
            letterSpacing: 0,
          ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
        ),
      ],
    );
  }
}

class _CountryCardWidget extends StatelessWidget {
  const _CountryCardWidget({
    required this.card,
    required this.selected,
    required this.connected,
    this.onTap,
    this.cachedDownloadMbps,
    this.cachedUploadMbps,
    required this.width,
    required this.minHeight,
  });

  final CountryCard card;
  final bool selected;
  final bool connected;
  final VoidCallback? onTap;
  final double? cachedDownloadMbps;
  final double? cachedUploadMbps;
  final double width;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final statusLabel = connected
        ? l10n.badgeConnected
        : selected
            ? l10n.badgeSelected
            : l10n.badgeConnect;
    final statusColor = connected
        ? HiVpnColors.success
        : theme.colorScheme.onSurface.withOpacity(0.85);
    final disabled = onTap == null;
    final downloadText = cachedDownloadMbps != null
        ? '${cachedDownloadMbps!.toStringAsFixed(1)} Mbps'
        : '--';
    final uploadText = cachedUploadMbps != null
        ? '${cachedUploadMbps!.toStringAsFixed(1)} Mbps'
        : '--';

    return Opacity(
      opacity: disabled ? 0.6 : 1,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: minHeight),
        child: Container(
          width: width,
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? theme.colorScheme.primary.withOpacity(0.1)
                : theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary.withOpacity(0.3)
                  : theme.colorScheme.outline.withOpacity(0.1),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _flagEmoji(card.countryCode),
                          style: const TextStyle(fontSize: 28),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceVariant
                                .withOpacity(0.5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            card.latencyLabel(l10n),
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color:
                                  theme.colorScheme.onSurface.withOpacity(0.8),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      card.localizedName(l10n),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    if (card.server != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        card.server!.hostName?.isNotEmpty ?? false
                            ? card.server!.hostName!
                            : card.server!.endpoint,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.7),
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _MetricTile(
                            label: l10n.serverDownloadLabel,
                            value: downloadText,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _MetricTile(
                            label: l10n.serverUploadLabel,
                            value: uploadText,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (card.isConnectable)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          statusLabel,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: statusColor,
                          ),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.outline.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          card.server == null
                              ? l10n.homeNoNodesAvailable
                              : l10n.homeServerTimeoutLabel,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _flagEmoji(String countryCode) {
    const base = 0x1F1E6;
    return countryCode.toUpperCase().characters.map((char) {
      final codeUnit = char.codeUnitAt(0) - 0x41 + base;
      return String.fromCharCode(codeUnit);
    }).join();
  }
}

class _ServerCard extends StatelessWidget {
  const _ServerCard({
    required this.server,
    required this.selected,
    required this.connected,
    this.onTap,
    this.latency,
    this.cachedDownloadMbps,
    this.cachedUploadMbps,
    required this.width,
    required this.minHeight,
  });

  final Server server;
  final bool selected;
  final bool connected;
  final VoidCallback? onTap;
  final int? latency;
  final double? cachedDownloadMbps;
  final double? cachedUploadMbps;
  final double width;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    final statusLabel = connected
        ? l10n.badgeConnected
        : selected
            ? l10n.badgeSelected
            : l10n.badgeConnect;
    final statusColor = connected
        ? HiVpnColors.success
        : theme.colorScheme.onSurface.withOpacity(0.85);
    final rawPing = server.pingMs ?? latency;
    final pingValue = (rawPing != null && rawPing < 9999) ? rawPing : null;
    final latencyText = pingValue != null ? '$pingValue ms' : '--';
    final downloadText = cachedDownloadMbps != null
        ? '${cachedDownloadMbps!.toStringAsFixed(1)} Mbps'
        : _formatBandwidth(server.downloadSpeed ?? server.bandwidth);
    final uploadText = cachedUploadMbps != null
        ? '${cachedUploadMbps!.toStringAsFixed(1)} Mbps'
        : _formatBandwidth(server.uploadSpeed);
    final sessionsValue = server.sessions;
    final hostLabel = (server.hostName?.isNotEmpty ?? false)
        ? server.hostName!
        : server.endpoint;
    final ipLabel = (server.ip?.isNotEmpty ?? false)
        ? server.ip!
        : server.endpoint.split(':').first;

    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight),
      child: Container(
        width: width,
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary.withOpacity(0.1)
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary.withOpacity(0.3)
                : theme.colorScheme.outline.withOpacity(0.1),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _flagEmoji(server.countryCode),
                        style: const TextStyle(fontSize: 28),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color:
                              theme.colorScheme.surfaceVariant.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          latencyText,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface.withOpacity(0.8),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    localizedServerDisplayName(server, l10n),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    hostLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                  if (ipLabel != hostLabel) ...[
                    const SizedBox(height: 4),
                    Text(
                      ipLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.6),
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _MetricTile(
                          label: l10n.serverDownloadLabel,
                          value: downloadText,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _MetricTile(
                          label: l10n.serverUploadLabel,
                          value: uploadText,
                        ),
                      ),
                    ],
                  ),
                  if (sessionsValue != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      l10n.serverSessionsLabel(sessionsValue),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      statusLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _flagEmoji(String countryCode) {
    final base = 0x1F1E6;
    return countryCode.toUpperCase().characters.map((char) {
      final codeUnit = char.codeUnitAt(0) - 0x41 + base;
      return String.fromCharCode(codeUnit);
    }).join();
  }

  String _formatBandwidth(int? bytesPerSecond) {
    final value = bytesPerSecond ?? 0;
    if (value <= 0) {
      return '--';
    }
    const units = ['B/s', 'KB/s', 'MB/s', 'GB/s'];
    var display = value.toDouble();
    var unitIndex = 0;
    while (display >= 1024 && unitIndex < units.length - 1) {
      display /= 1024;
      unitIndex++;
    }
    return '${display.toStringAsFixed(1)} ${units[unitIndex]}';
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LiquidGlass(
      borderRadius: BorderRadius.circular(16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      blurSigma: 10,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.65),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionStatusBadge extends StatelessWidget {
  const _ConnectionStatusBadge({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface.withOpacity(0.8),
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.6),
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: Text(
            value,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
        ),
      ],
    );
  }
}
