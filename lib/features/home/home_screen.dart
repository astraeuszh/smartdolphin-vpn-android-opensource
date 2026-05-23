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
import '../../../core/errors/error_codes.dart';
import '../../../core/errors/error_dialog.dart';
import '../../theme/colors.dart';
import '../../widgets/connect_control.dart';
import '../../widgets/frosted_glass.dart';
import '../../l10n/app_localizations.dart';
import '../dashboard/domain/ip_info_provider.dart';
import '../../../l10n/country_names.dart';
import '../home/domain/home_local_stats_provider.dart';
import '../dashboard/presentation/dashboard_screen.dart';
import '../servers/data/country_card.dart';
import '../servers/domain/server.dart';
import '../connection/domain/tunnel_throughput_provider.dart';
import '../servers/data/server_preferences_repository.dart';
import '../servers/domain/server_providers.dart';
import '../servers/domain/server_display_name.dart';
import '../servers/presentation/server_picker_sheet.dart';
import '../auth/domain/auth_controller.dart';
import '../session/domain/session_controller.dart';
import '../../services/vpn/vpn_provider.dart';
import '../session/domain/session_state.dart';
import '../session/domain/session_status.dart';
import '../session/presentation/countdown.dart';
import '../speedtest/presentation/speedtest_screen.dart';
import '../settings/presentation/settings_screen.dart';
import '../../services/remote/console_announcements.dart';
import '../../services/storage/prefs.dart';
import '../usage/data_usage_controller.dart';
import '../game_mode/domain/game_mode_controller.dart';
import '../game_mode/domain/game_mode_overlay_provider.dart';
import '../game_mode/domain/game_mode_speed.dart';
import '../game_mode/domain/game_traffic_providers.dart';
import '../game_mode/presentation/game_mode_screen.dart';
import '../usage/data_usage_state.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

const _actionDebounceMs = 600;
const _dismissedAnnouncementsKey = 'announcements.dismissed_ids';

class _HomeScreenState extends ConsumerState<HomeScreen> with WidgetsBindingObserver {
  final GlobalKey _serverCarouselKey = GlobalKey();
  final GlobalKey _connectKey = GlobalKey();
  final GlobalKey _statusKey = GlobalKey();
  final GlobalKey _speedTabKey = GlobalKey();
  int _tabIndex = 0;
  bool _navDragging = false;
  double? _navIndicatorLeft;
  /// 游戏模式全屏：底栏收起，入口为小球。
  bool _gameModeExpanded = false;
  bool _didSchedulePostFrameCallback = false;
  DateTime? _lastConnectTap;
  DateTime? _lastSwitchTap;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final paused = state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached;
    ref.read(serverCatalogProvider.notifier).setLatencyPollingPaused(paused);
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
    unawaited(_maybeShowAnnouncement());
    final auth = ref.read(authControllerProvider);
    if (auth.status == AuthStatus.authenticated &&
        auth.session?.canUseVpn == true) {
      unawaited(
        ref.read(sessionControllerProvider.notifier).autoConnectIfEnabled(
              context: context,
            ),
      );
    }
    unawaited(_warmUpVpn());
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

  Future<void> _dismissAnnouncementId(int id) async {
    final prefs = await ref.read(prefsStoreProvider.future);
    final dismissed = await _loadDismissedAnnouncementIds(prefs);
    dismissed.add(id);
    await prefs.setString(
      _dismissedAnnouncementsKey,
      jsonEncode(dismissed.toList()),
    );
  }

  Future<void> _maybeShowAnnouncement() async {
    if (!mounted) return;
    try {
      final rows = await ConsoleAnnouncements().fetchPublished();
      if (rows.isEmpty || !mounted) return;

      final prefs = await ref.read(prefsStoreProvider.future);
      final dismissed = await _loadDismissedAnnouncementIds(prefs);
      final unseen = rows.where((row) => !dismissed.contains(row.id)).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      if (unseen.isEmpty || !mounted) return;

      final announcement = unseen.first;
      final l10n = AppLocalizations.of(context);
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text(announcement.title),
          content: SingleChildScrollView(
            child: Text(announcement.body),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('已知晓'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l10n.close),
            ),
          ],
        ),
      );
      if (!mounted) return;
      await _dismissAnnouncementId(announcement.id);
    } catch (e, st) {
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
        final connected =
            ref.read(sessionControllerProvider).status == SessionStatus.connected;
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
    if (next.pendingTraffic90Dialog && !(previous?.pendingTraffic90Dialog ?? false)) {
      final l10n = AppLocalizations.of(context);
      unawaited(
        showErrorDialog(
          context,
          message: l10n.homeTrafficUsageLowMessage,
          errorCode: ecTrafficQuota90,
          title: l10n.homeTrafficUsageTitle,
          onClose: () {
            unawaited(
              ref.read(dataUsageControllerProvider.notifier).clearTraffic90Dialog(),
            );
          },
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<SessionState>(sessionControllerProvider, _onSessionChanged);
    ref.listen<DataUsageState>(dataUsageControllerProvider, _onDataUsageChanged);
    final l10n = context.l10n;
    final theme = Theme.of(context);
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
    return FrostedGlass(
      borderRadius: BorderRadius.circular(999),
      blurSigma: blurSigma,
      surface: GlassSurface.nav,
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
            final pillLeft = _navIndicatorLeft ?? (indicatorLeft(_tabIndex) + 4);

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
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 5,
                            offset: const Offset(0, 1),
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
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Icon(
                          Icons.sports_esports_rounded,
                          color: theme.colorScheme.onSurfaceVariant,
                          size: 26,
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
      color: selected ? cs.primary : cs.onSurfaceVariant.withValues(alpha: 0.88),
    );
  }

  Widget _buildHomeTab(BuildContext context, AppLocalizations l10n) {
    final session = ref.watch(sessionControllerProvider);
    final selectedServer = ref.watch(selectedServerProvider);
    final liveThroughput = ref.watch(tunnelThroughputProvider);
    final speedCache = ref.watch(serverSpeedCacheProvider);
    final theme = Theme.of(context);
    final statusBadgeLabel = _statusBadgeLabel(session.status, l10n);
    final statusBadgeColor = _statusDotColor(session.status);
    final titleBaseStyle = theme.textTheme.headlineSmall ?? const TextStyle(fontSize: 24);
    final titleStyle = titleBaseStyle.copyWith(fontWeight: FontWeight.w700);

    final isPreparing = session.status == SessionStatus.preparing;
    final isConnecting = session.status == SessionStatus.connecting;
    final isAttemptCancelable = isPreparing || isConnecting;
    final isBusy = isAttemptCancelable;
    final isConnected = session.status == SessionStatus.connected;
    final bottomNavReserve = 88.0 + MediaQuery.paddingOf(context).bottom;
    final buttonState = isConnected
        ? ConnectButtonVisualState.active
        : isAttemptCancelable
            ? ConnectButtonVisualState.connecting
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
                    child: _ConnectionStatusBadge(
                      label: statusBadgeLabel,
                      color: statusBadgeColor,
                    ),
                  ),
                ],
              ),
              if (session.status == SessionStatus.error && session.errorMessage != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: theme.colorScheme.error, size: 24),
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
                  child: FrostedGlass(
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    borderRadius: BorderRadius.circular(22),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    surface: GlassSurface.raised,
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
                                selectedServer?.name ?? l10n.selectServerToBegin,
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
                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.62),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
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
                            enabled: !isBusy || isAttemptCancelable,
                            isActive: isConnected,
                            isLoading: isBusy,
                            visualState: buttonState,
                            label: isConnected
                                ? l10n.disconnect
                                : isAttemptCancelable
                                    ? l10n.statusConnecting
                                    : l10n.connect,
                            statusText: isAttemptCancelable ? l10n.tapToCancel : null,
                            onTap: () async {
                              await ref.read(hapticsServiceProvider).impact();
                              if (isConnected) {
                                unawaited(_safeDisconnect(ref));
                              } else if (isAttemptCancelable) {
                                unawaited(_safeDisconnect(ref));
                              } else {
                                final server = selectedServer;
                                if (server == null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(l10n.pleaseSelectServer)),
                                  );
                                  return;
                                }
                                final ok = await ref
                                    .read(authControllerProvider.notifier)
                                    .ensureVpnAccess();
                                if (!ok) {
                                  final msg = ref.read(authControllerProvider).message ??
                                      l10n.homeLoginVpnRequired;
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(msg)),
                                    );
                                  }
                                  return;
                                }
                                await ref
                                    .read(sessionControllerProvider.notifier)
                                    .connect(context: context, server: server);
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
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.52),
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
    final ipInfo = ref.watch(ipInfoProvider).valueOrNull;
    final localStats = !isConnected
        ? ref.watch(homeLocalStatsPeriodicProvider).valueOrNull
        : null;
    final latencyMap = ref.watch(serverLatencyProvider);
    final cached = server != null ? speedCache[server!.id] : null;
    final useLive = isConnected &&
        server != null &&
        (liveThroughput.downloadMbps != null || liveThroughput.uploadMbps != null);

    String downloadText = '--';
    String uploadText = '--';
    if (isConnected) {
      if (useLive) {
        if (liveThroughput.downloadMbps != null && liveThroughput.downloadMbps! > 0.05) {
          downloadText = '${liveThroughput.downloadMbps!.toStringAsFixed(1)} Mbps';
        }
        if (liveThroughput.uploadMbps != null && liveThroughput.uploadMbps! > 0.05) {
          uploadText = '${liveThroughput.uploadMbps!.toStringAsFixed(1)} Mbps';
        }
      } else if (cached != null) {
        downloadText = '${cached.downloadMbps.toStringAsFixed(1)} Mbps';
        uploadText = '${cached.uploadMbps.toStringAsFixed(1)} Mbps';
      } else if (server != null) {
        downloadText = _formatBandwidth(server!.downloadSpeed ?? server!.bandwidth);
        uploadText = _formatBandwidth(server!.uploadSpeed);
      }
    } else if (localStats != null) {
      if (localStats.downloadMbps != null && localStats.downloadMbps! > 0) {
        downloadText = '${localStats.downloadMbps!.toStringAsFixed(1)} Mbps';
      }
      if (localStats.uploadMbps != null && localStats.uploadMbps! > 0) {
        uploadText = '${localStats.uploadMbps!.toStringAsFixed(1)} Mbps';
      }
    }

    final ipText = isConnected
        ? ((publicIp?.isNotEmpty ?? false) ? publicIp! : (ipInfo?.ip ?? '--'))
        : (localStats?.ip ?? ipInfo?.ip ?? '--');
    final addressText = _physicalAddress(l10n, server, ipInfo, isConnected, localStats);

    int? targetLatencyMs;
    if (isConnected && server != null) {
      final measured = latencyMap[server!.id];
      final rawPing = measured ?? server!.pingMs;
      if (rawPing != null && rawPing > 0 && rawPing < 9999) {
        targetLatencyMs = rawPing;
      }
    } else if (!isConnected) {
      targetLatencyMs = localStats?.latencyMs;
    }
    final latencyText = targetLatencyMs != null ? '$targetLatencyMs ms' : '--';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _HomeStatCard(
                  label: l10n.serverUploadLabel,
                  value: uploadText,
                  theme: theme,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _HomeStatCard(
                  label: l10n.serverDownloadLabel,
                  value: downloadText,
                  theme: theme,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FrostedGlass(
            borderRadius: BorderRadius.circular(20),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            surface: GlassSurface.raised,
            child: Row(
              children: [
                Expanded(
                  child: _HomeInfoCell(
                    label: l10n.speedTestIpLabel,
                    value: ipText,
                    theme: theme,
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
                    label: l10n.networkLocation,
                    value: addressText,
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
    final cc = (localStats?.countryCode ?? ipInfo?.countryCode ?? '').toUpperCase();
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
    return FrostedGlass(
      borderRadius: BorderRadius.circular(20),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      surface: GlassSurface.raised,
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
  });

  final String label;
  final String value;
  final ThemeData theme;

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
            fontSize: 12,
          ),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
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
                            color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            card.latencyLabel(l10n),
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
                          card.server == null ? l10n.homeNoNodesAvailable : l10n.homeServerTimeoutLabel,
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
                          color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
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
    return FrostedGlass(
      borderRadius: BorderRadius.circular(16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      surface: GlassSurface.flat,
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
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
        ),
      ],
    );
  }
}
