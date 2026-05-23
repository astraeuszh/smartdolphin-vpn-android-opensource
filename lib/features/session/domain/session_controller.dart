import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openvpn_flutter/openvpn_flutter.dart';

import '../../../core/device/device_memory_tier_provider.dart';
import '../../../core/device/memory_tier.dart';
import '../../../core/platform/runtime_platform.dart';
import '../../../core/errors/app_error.dart';
import '../../../core/errors/error_codes.dart';
import '../../../core/session/session_limits.dart';
import '../../../core/utils/iterable_extensions.dart';
import '../../../platform/android/background_keep_alive.dart';
import '../../../services/notifications/session_notification_service.dart';
import '../../../services/storage/prefs.dart';
import '../../../services/time/session_clock.dart';
import '../../../services/time/session_clock_provider.dart';
import '../../../services/device/battery_exemption_service.dart';
import '../../../services/logging/error_reporter.dart';
import '../../../services/logging/vpn_logger.dart';
import '../../../services/vpn/openvpn_port.dart';
import '../../../services/vpn/vpn_provider.dart';
import '../../../services/vpn/models/vpn.dart';
import '../../servers/data/static_servers.dart';
import '../../servers/domain/server.dart';
import '../../servers/domain/server_providers.dart';
import '../../settings/domain/settings_controller.dart';
import '../../settings/domain/traffic_mode.dart';
import '../../settings/domain/vpn_protocol.dart';
import '../../speedtest/domain/speedtest_controller.dart';
import '../../speedtest/domain/speedtest_state.dart';
import '../../game_mode/domain/game_decel_tier_controller.dart';
import '../../game_mode/domain/game_mode_controller.dart';
import '../../game_mode/domain/game_mode_overlay_provider.dart';
import '../../smart_stable/smart_stable_notifier.dart';
import '../../auth/domain/auth_controller.dart';
import '../../usage/data_usage_controller.dart';
import 'session_meta.dart';
import 'session_state.dart';
import 'session_status.dart';

const _sessionMetaPrefsKey = 'session_meta_v1';

const sessionDuration = kMaxSessionWallDuration;
const _dataLimitMessage = '已达到流量上限，无法继续使用';
const _connectionTimeoutDuration = Duration(seconds: 30);

class SessionController extends StateNotifier<SessionState> {
  SessionController(this._ref)
      : _vpnPort = _ref.read(openVpnPortProvider),
        _clock = _ref.read(sessionClockProvider),
        _settings = _ref.read(settingsControllerProvider.notifier),
        _vpnLogger = _ref.read(vpnLoggerProvider),
        _notificationService =
            _ref.read(sessionNotificationServiceProvider),
        super(SessionState.initial()) {
    _speedSubscription =
        _ref.listen<SpeedTestState>(speedTestControllerProvider, _onSpeedUpdate);
    // Web: flutter_local_notifications initialize() may never complete; skip.
    if (!kIsWeb) {
      unawaited(
        _notificationService.initialize(onAction: _handleNotificationAction),
      );
    }
    _stageSubscription = _vpnPort.stageStream.listen((stage) {
      unawaited(_handleVpnStage(stage));
    });
    _bootstrap();
  }

  final Ref _ref;
  final OpenVpnPort _vpnPort;
  final SessionClock _clock;
  final SettingsController _settings;
  final SessionNotificationService _notificationService;
  final VpnLogger _vpnLogger;

  Timer? _ticker;
  Timer? _connectionTimeoutTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  StreamSubscription<String>? _intentSubscription;
  StreamSubscription<VPNStage>? _stageSubscription;
  late final ProviderSubscription<SpeedTestState> _speedSubscription;
  int _reconnectAttempts = 0;
  bool _pendingAutoConnect = false;
  int _tickCounter = 0;
  SessionMeta? _activeMeta;
  Server? _queuedServer;
  _PendingConnection? _pendingConnection;
  Server? _currentServer;
  bool _manualDisconnectInProgress = false;
  int? _lastTickRx;
  int? _lastTickTx;

  static int _parseBytes(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toInt();
    final s = value.toString().trim().replaceAll(RegExp(r'[,\s]'), '');
    return int.tryParse(s) ?? 0;
  }

  void _log(String message) {
    debugPrint('[SessionController] $message');
    _vpnLogger.info('[Session] $message');
  }

  void _setError(int code, {String? details, Object? cause, String? displayMessage}) {
    final wasConnected = state.status == SessionStatus.connected;
    final wasConnecting = state.status == SessionStatus.connecting ||
        state.status == SessionStatus.preparing;
    final err = AppError(code, details: details ?? '', cause: cause, displayMessage: displayMessage);
    logAppError(err, 'SessionController');
    state = state.copyWith(
      status: SessionStatus.error,
      errorMessage: err.message,
      errorCode: code,
    );
    if (wasConnected || wasConnecting || _pendingConnection != null) {
      unawaited(
        _ref.read(errorReporterProvider).reportVpnError(
              errorCode: code,
              message: err.message,
              details: details ?? '',
            ),
      );
    }
  }

  void _startConnectionTimeout() {
    _cancelConnectionTimeout();
    _connectionTimeoutTimer = Timer(_connectionTimeoutDuration, () {
      if (state.status != SessionStatus.connecting ||
          _pendingConnection == null) {
        return;
      }
      _log('Connection timed out after ${_connectionTimeoutDuration.inSeconds}s');
      _stopConnectivityWatch();
      final pending = _pendingConnection;
      _pendingConnection = null;
      _setError(ecNodeConnTimeout, details: 'timeout ${_connectionTimeoutDuration.inSeconds}s');
      unawaited(_notificationService.clear());
      if (pending != null) {
        unawaited(_vpnPort.disconnect());
      }
    });
  }

  void _cancelConnectionTimeout() {
    _connectionTimeoutTimer?.cancel();
    _connectionTimeoutTimer = null;
  }

  void _startConnectivityWatch() {
    _stopConnectivityWatch();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      final hasNetwork = results.isNotEmpty &&
          !results.every((r) => r == ConnectivityResult.none);
      if (!hasNetwork && state.status == SessionStatus.connecting && _pendingConnection != null) {
        _log('Network lost during connection');
        _abortConnectionForNetworkLost();
      }
    });
  }

  void _stopConnectivityWatch() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
  }

  void _abortConnectionForNetworkLost() {
    if (state.status != SessionStatus.connecting || _pendingConnection == null) return;
    _cancelConnectionTimeout();
    _stopConnectivityWatch();
    final pending = _pendingConnection;
    _pendingConnection = null;
    unawaited(_notificationService.clear());
    _setError(ecLocalNetDisconnected, details: 'network lost');
    unawaited(_vpnPort.disconnect());
  }

  Future<void> _bootstrap() async {
    _intentSubscription = _vpnPort.intentActions.listen(_handleIntentAction);
    await _restoreSession();
    _pendingAutoConnect = true;
  }

  void _handleIntentAction(String action) {
    final normalized = action.toLowerCase();
    if (normalized.contains('disconnect')) {
      unawaited(disconnect(userInitiated: false));
    }
  }

  Future<void> _handleNotificationAction(String action) async {
    if (action == SessionNotificationService.actionDisconnect) {
      await disconnect();
    }
  }

  Future<void> _handleVpnStage(VPNStage stage) async {
    _log('VPN stage update: $stage');
    if (_manualDisconnectInProgress) {
      if (stage == VPNStage.disconnected) {
        _manualDisconnectInProgress = false;
      }
      return;
    }
    if (stage == VPNStage.connected) {
      await _completePendingConnection();
      return;
    }

    if (_stageIndicatesFailure(stage)) {
      // Ignore transient stages during connection startup / server switch
      if (_pendingConnection != null) {
        if (stage == VPNStage.unknown) {
          _log('Ignoring transient unknown (noprocess) during connection');
          return;
        }
        if (stage == VPNStage.disconnected) {
          _log('Ignoring disconnected (teardown of previous session) during connect');
          return;
        }
      }
      _cancelConnectionTimeout();
      _stopConnectivityWatch();
      final pending = _pendingConnection;
      if (pending != null) {
        _pendingConnection = null;
        await _notificationService.clear();
        final code = _errorCodeForStage(stage);
        _setError(code, details: 'server=${pending.server.name}');
        return;
      }
      if (state.status == SessionStatus.connecting ||
          state.status == SessionStatus.preparing) {
        await _notificationService.clear();
        final code = _errorCodeForStage(stage);
        _setError(code);
        return;
      }
      if (state.status == SessionStatus.connected) {
        await _handleRemoteDisconnect();
      }
    }
    
    // Add logging for all stage changes
    _log('VPN stage changed to: $stage');
  }

  int _errorCodeForStage(VPNStage stage) {
    switch (stage) {
      case VPNStage.unknown:
        return ecNodeConnRefused;
      case VPNStage.denied:
        return ecVpnPermissionDenied;
      case VPNStage.error:
        return ecCoreStartFailed;
      case VPNStage.disconnected:
        return ecNodeDisconnected;
      default:
        return ecNodeConfigFailed;
    }
  }

  bool _stageIndicatesFailure(VPNStage stage) {
    switch (stage) {
      case VPNStage.unknown:
      case VPNStage.disconnected:
      case VPNStage.denied:
      case VPNStage.error:
      case VPNStage.exiting:
        return true;
      default:
        return false;
    }
  }

  Future<void> _completePendingConnection() async {
    _cancelConnectionTimeout();
    _stopConnectivityWatch();
    final pending = _pendingConnection;
    if (pending == null) {
      return;
    }
    _pendingConnection = null;
    final server = pending.server;
    final start = DateTime.now().toUtc();
    final publicIp = pending.initialIp;
    final meta = SessionMeta(
      serverId: server.id,
      serverName: server.name,
      countryCode: server.countryCode,
      startElapsedMs: pending.startElapsedMs,
      durationMs: sessionDuration.inMilliseconds,
      publicIp: publicIp,
    );
    _activeMeta = meta;
    _currentServer = server;
    state = state.copyWith(
      status: SessionStatus.connected,
      start: start,
      duration: sessionDuration,
      startElapsedMs: pending.startElapsedMs,
      serverId: server.id,
      serverName: server.name,
      countryCode: server.countryCode,
      publicIp: publicIp,
      expired: false,
      sessionLocked: true,
      meta: meta,
      errorMessage: null,
    );
    await _persistMeta(meta);
    await _ref.read(serverCatalogProvider.notifier).rememberSelection(server);
    _reconnectAttempts = 0;
    _queuedServer = null;
    if (isAndroidNative) {
      unawaited(setHasActiveSession(true));
      unawaited(maybeRequestBatteryExemptionOnce(_ref));
    }

    final remaining = await _clock.remaining(
      startElapsedMs: pending.startElapsedMs,
      duration: sessionDuration,
    );
    await _notificationService.showConnected(
      server: server,
      remaining: remaining,
      state: state,
    );
    _startTicker();
  }

  Future<void> _handleRemoteDisconnect() async {
    final server = _currentServer;
    if (server != null && _ref.read(settingsControllerProvider).autoConnect.reconnectOnNetworkChange) {
      _log('Unexpected disconnect; attempting auto-reconnect to ${server.name}');
      await _tryAutoReconnect(server);
      return;
    }
    _setError(ecNodeDisconnected, details: 'Remote disconnect');
    await _forceDisconnect(clearPrefs: true, preserveError: true);
  }

  static const _reconnectDelays = [
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
  ];

  Future<void> _tryAutoReconnect(Server server) async {
    for (var i = 0; i < _reconnectDelays.length; i++) {
      await Future<void>.delayed(_reconnectDelays[i]);
      if (state.status == SessionStatus.connected || _manualDisconnectInProgress) {
        return;
      }
      _log('Auto-reconnect attempt ${i + 1}/${_reconnectDelays.length}');
      await connect(server: server);
      await Future<void>.delayed(const Duration(seconds: 1));
      if (state.status == SessionStatus.connected) {
        _log('Auto-reconnect succeeded');
        return;
      }
    }
    _log('Auto-reconnect failed after ${_reconnectDelays.length} attempts');
    await _forceDisconnect(clearPrefs: true);
  }

  void _onSpeedUpdate(SpeedTestState? previous, SpeedTestState next) {
    final ip = next.ip;
    if (state.status != SessionStatus.connected || ip == null || ip.isEmpty) {
      return;
    }
    if (state.publicIp == ip) {
      return;
    }
    state = state.copyWith(publicIp: ip);
    final meta = _activeMeta;
    if (meta != null) {
      final updated = meta.copyWith(publicIp: ip);
      _activeMeta = updated;
      state = state.copyWith(meta: updated);
      unawaited(_persistMeta(updated));
      unawaited(_vpnPort.extendSession(updated.duration, publicIp: ip));
    }
  }

  Future<void> _restoreSession() async {
    final prefs = await _ref.read(prefsStoreProvider.future);
    final stored = prefs.getString(_sessionMetaPrefsKey);
    if (stored == null) {
      state = SessionState.initial();
      return;
    }
    try {
      final jsonMap = jsonDecode(stored) as Map<String, dynamic>;
      final meta = SessionMeta.fromJson(jsonMap);
      final remaining = await _clock.remaining(
        startElapsedMs: meta.startElapsedMs,
        duration: meta.duration,
      );
      final connected = await _vpnPort.isConnected();
      if (!connected || remaining == Duration.zero) {
        await _forceDisconnect(clearPrefs: true);
        return;
      }
      final elapsed = meta.duration - remaining;
      final startWall = DateTime.now().toUtc().subtract(elapsed);
      _activeMeta = meta;
      state = state.copyWith(
        status: SessionStatus.connected,
        start: startWall,
        duration: meta.duration,
        startElapsedMs: meta.startElapsedMs,
        serverId: meta.serverId,
        serverName: meta.serverName,
        countryCode: meta.countryCode,
        publicIp: meta.publicIp,
        expired: false,
        sessionLocked: true,
        meta: meta,
      );
      await _vpnPort.extendSession(Duration.zero);
      _startTicker();
    } catch (_) {
      await prefs.remove(_sessionMetaPrefsKey);
      state = SessionState.initial();
    }
  }

  Future<void> connect({
    BuildContext? context,
    required Server server,
    bool fromSmartStableReconnect = false,
  }) async {
    _log('connect() requested for ${server.name} (${server.countryCode})');
    final trafficPolicy = _ref.read(authControllerProvider).session?.trafficPolicy;
    if (trafficPolicy?.overQuota == true) {
      _setError(
        ecTrafficLimited,
        details: _dataLimitMessage,
        displayMessage: _dataLimitMessage,
      );
      return;
    }
    if (!fromSmartStableReconnect &&
        state.status == SessionStatus.disconnected) {
      _ref.read(smartStableProvider.notifier).clearDeclineSuppressForNewUserConnect();
    }
    final routing = _ref.read(settingsControllerProvider).routing;
    if (routing.mode == TrafficMode.rule) {
      final hasRules = routing.ruleDb.customRules
          .split(RegExp(r'\r?\n'))
          .any((line) {
            final t = line.trim();
            return t.isNotEmpty && !t.startsWith('#');
          });
      if (!hasRules) {
        _setError(
          ecNodeConfigFailed,
          details: 'rule mode empty',
          displayMessage: '规则模式需要至少填写一条分流规则',
        );
        return;
      }
    }
    if (state.status == SessionStatus.connected) {
      _log('Ignoring connect: already connected');
      return;
    }
    // Prevent double-connect: if we're already connecting to the same server,
    // ignore. A second connect() would call disconnect() first (in openvpn_port)
    // and tear down the tunnel we're about to establish.
    if (state.status == SessionStatus.connecting &&
        _pendingConnection != null &&
        _pendingConnection!.server.id == server.id) {
      _log('Ignoring duplicate connect: already connecting to ${server.name}');
      return;
    }
    if (!_vpnPort.isSupported) {
      _log('Device does not support VPN');
      _setError(ecCoreStartFailed, details: 'VPN not supported');
      return;
    }
    final settingsState = _ref.read(settingsControllerProvider);
    if (!settingsState.protocol.protocol.isSupported) {
      _log('Protocol not supported: ${settingsState.protocol.protocol}');
      _setError(ecNodeConfigFailed, details: 'Protocol not supported');
      return;
    }
    // 立即显示「正在连接」状态，让用户感觉秒连
    state = state.copyWith(
      status: SessionStatus.connecting,
      errorMessage: null,
    );
    await Future<void>.delayed(Duration.zero); // yield so UI paints orange immediately

    // 连接前检查网络，已离线则立即报错
    final results = await Connectivity().checkConnectivity();
    final hasNetwork = results.isNotEmpty &&
        !results.every((r) => r == ConnectivityResult.none);
    if (!hasNetwork) {
      _setError(ecLocalNetDisconnected, details: 'no network');
      return;
    }

    MemoryTier tier = MemoryTier.mid;
    try {
      tier = await _ref.read(deviceMemoryTierProvider.future);
    } catch (_) {
      // keep mid
    }
    _vpnPort.setMemoryTier(tier);

    // 请求 VPN 权限（已有权限时几乎无延迟）
    final prepared = await _vpnPort.prepare();
    _log('VPN permission request result: $prepared');
    if (!prepared) {
      _setError(ecVpnPermissionDenied, details: 'VPN permission required');
      return;
    }
    _log('Connecting to VPN ${server.name} (${server.countryCode})');

    try {
      final settingsState = _ref.read(settingsControllerProvider);
      final smartStable = _ref.read(smartStableProvider);
      _vpnPort.setSmartStableTuning(smartStable.tuningEnabled);
      _vpnPort.setGameTrafficMode(_ref.read(gameModeControllerProvider));
      _vpnPort.setGameDecelTier(_ref.read(gameDecelTierProvider));
      _vpnPort.setGameModeOverlayActive(_ref.read(gameModeOverlayActiveProvider));
      _vpnPort.setRoutingConfig(settingsState.routing);
      _vpnPort.setDnsServers(settingsState.protocol.resolvedDnsServers);
      final initialIp = _ref.read(speedTestControllerProvider).ip;
      final startElapsed = await _clock.elapsedRealtime();

      // SmartDolphin 自有节点：优先使用 static_servers 中的配置，避免缓存数据损坏
      final configBase64 = _resolveConfigBase64(server);

      // Convert Server to Vpn model for OpenVPN connection
      final vpnServer = Vpn(
        hostName: server.hostName ?? server.name,
        ip: server.ip ?? '',
        ping: server.pingMs?.toString() ?? '0',
        speed: server.downloadSpeed ?? server.bandwidth ?? 0,
        countryLong: server.countryName ?? server.name,
        countryShort: server.countryCode,
        numVpnSessions: server.sessions ?? 0,
        openVpnConfigDataBase64: configBase64,
      );

      // Validate that we have a configuration
      if (configBase64.isEmpty) {
        _log('Missing OpenVPN config for server ${server.id}');
        _setError(ecNodeConfigFailed, details: 'No config for server ${server.id}');
        return;
      }

      try {
        final decodedConfig = vpnServer.openVpnConfig;
        if (decodedConfig.trim().isEmpty) {
          _log('Missing OpenVPN config for server ${server.id}');
          _setError(ecNodeConfigFailed, details: 'Empty config');
          return;
        }
      } on AppError catch (error) {
        _log('Invalid OpenVPN config for server ${server.id}: $error');
        _setError(ecNodeConfigFailed, details: error.toString());
        return;
      }

      _pendingConnection = _PendingConnection(
        server: server,
        startElapsedMs: startElapsed,
        initialIp: initialIp,
      );
      await _notificationService.showConnecting(server);
      _startConnectionTimeout();
      _startConnectivityWatch();

      _log('Attempting to connect to VPN server: ${vpnServer.hostName}, IP: ${vpnServer.ip}');
      _log('Config length: ${vpnServer.openVpnConfig.length}');
      
      final connected = await _vpnPort.connect(vpnServer);
      _log('OpenVPN connect() returned $connected');
      if (!connected) {
        _cancelConnectionTimeout();
        _stopConnectivityWatch();
        _pendingConnection = null;
        await _notificationService.clear();
        _setError(ecCoreStartFailed, details: 'connect() returned false');
        return;
      }
    } catch (e) {
      _log('Connection error: $e');
      _cancelConnectionTimeout();
      _stopConnectivityWatch();
      _pendingConnection = null;
      await _notificationService.clear();
      _setError(ecNetworkUnstable, details: e.toString(), cause: e);
    }
  }

  Future<void> disconnect({bool userInitiated = true}) async {
    _log('disconnect() requested. Status: ${state.status}, userInitiated: $userInitiated');
    if (_manualDisconnectInProgress) {
      _log('Ignoring duplicate disconnect (already in progress)');
      return;
    }
    _manualDisconnectInProgress = true;
    _cancelConnectionTimeout();
    _stopConnectivityWatch();
    _stopTicker();
    _pendingConnection = null;

    try {
      final wasConnected = state.status == SessionStatus.connected;
      final previousState = state;

      // Reset UI state FIRST so user sees disconnect immediately (avoids crash blocking UI)
      _activeMeta = null;
      _currentServer = null;
      state = SessionState.initial();
      if (isAndroidNative) {
        unawaited(setHasActiveSession(false));
      }
      _applyQueuedServerSelection();

      // Tear down VPN and notification in background
      try {
        await _vpnPort.disconnect();
      } catch (e) {
        _log('disconnect: VPN tear-down error (ignored): $e');
      }
      try {
        await _notificationService.clear();
      } catch (_) {}

      // Persist history in background
      if (wasConnected) {
        try {
          final server = _resolveHistoryServer(fromState: previousState);
          final meta = previousState.meta;
          final stats = <String, dynamic>{};
          try {
            stats.addAll(await _vpnPort.getTunnelStats());
          } catch (_) {}
          Duration? actualDuration;
          if (meta != null) {
            try {
              final nowMs = await _clock.elapsedRealtime();
              actualDuration = Duration(milliseconds: (nowMs - meta.startElapsedMs).clamp(0, meta.durationMs).toInt());
            } catch (_) {}
          }
          final sessionForHistory = actualDuration != null
              ? previousState.copyWith(duration: actualDuration)
              : previousState;
          await _settings.recordSessionEnd(sessionForHistory, server: server, stats: stats);
          await _clearPersistedState();
        } catch (_) {}
      }
    } catch (e, st) {
      _log('disconnect: unexpected error (recovering): $e');
      debugPrintStack(stackTrace: st);
      _activeMeta = null;
      _currentServer = null;
      _pendingConnection = null;
      state = SessionState.initial();
      _applyQueuedServerSelection();
    } finally {
      _manualDisconnectInProgress = false;
    }
  }

  String _resolveConfigBase64(Server server) {
    final staticMatch = smartDolphinStaticServers.firstWhereOrNull(
      (s) => s.id == server.id,
    );
    if (staticMatch != null && staticMatch.openVpnConfigDataBase64 != null) {
      return staticMatch.openVpnConfigDataBase64!;
    }
    return server.openVpnConfigDataBase64 ?? '';
  }

  Server? _resolveHistoryServer({SessionState? fromState}) {
    final id = (fromState ?? state).serverId;
    final catalog = _ref.read(serverCatalogProvider);
    if (id != null) {
      final match = catalog.servers.firstWhereOrNull((s) => s.id == id);
      if (match != null) {
        return match;
      }
    }
    return _ref.read(selectedServerProvider);
  }

  Future<void> _forceDisconnect({
    bool clearPrefs = false,
    bool preserveError = false,
    bool markExpired = true,
  }) async {
    _cancelConnectionTimeout();
    _stopConnectivityWatch();
    _stopTicker();
    await _vpnPort.disconnect();
    if (clearPrefs) {
      await _clearPersistedMeta();
    }
    _activeMeta = null;
    _pendingConnection = null;
    await _notificationService.clear();
    _currentServer = null;
    _manualDisconnectInProgress = false;
    if (preserveError && state.status == SessionStatus.error) {
      state = state.copyWith(expired: markExpired, sessionLocked: false);
    } else {
      state = SessionState.initial().copyWith(expired: markExpired, sessionLocked: false);
    }
    _applyQueuedServerSelection();
  }

  Future<void> _persistMeta(SessionMeta meta) async {
    final prefs = await _ref.read(prefsStoreProvider.future);
    final jsonStr = jsonEncode(meta.toJson());
    await prefs.setString(_sessionMetaPrefsKey, jsonStr);
  }

  Future<void> _clearPersistedMeta() async {
    final prefs = await _ref.read(prefsStoreProvider.future);
    await prefs.remove(_sessionMetaPrefsKey);
  }

  Future<void> _clearPersistedState() async {
    await _clearPersistedMeta();
  }

  void _applyQueuedServerSelection() {
    final queued = _queuedServer;
    if (queued == null) {
      return;
    }
    _ref.read(selectedServerProvider.notifier).select(queued);
    _queuedServer = null;
  }

  void _startTicker() {
    _ticker?.cancel();
    _lastTickRx = null;
    _lastTickTx = null;
    _tickCounter = 0;
    _ticker = Timer.periodic(const Duration(seconds: 2), (_) async {
      _tickCounter += 1;
      final settings = _ref.read(settingsControllerProvider);
      if (settings.batterySaverEnabled && _tickCounter % 2 != 0) {
        return;
      }
      if (state.status != SessionStatus.connected ||
          state.startElapsedMs == null ||
          state.duration == null) {
        return;
      }
      final remaining = await _clock.remaining(
        startElapsedMs: state.startElapsedMs!,
        duration: state.duration!,
      );
      if (remaining <= Duration.zero) {
        await _forceDisconnect(clearPrefs: true, markExpired: false);
        _setError(
          ecSessionTimerCap,
          details: 'session wall time',
          displayMessage: '当前服务出现错误，请重新启动该服务',
        );
        return;
      }
      try {
        final stats = await _vpnPort.getTunnelStats();
        final rx = _parseBytes(stats['byte_in'] ?? stats['rxBytes']);
        final tx = _parseBytes(stats['byte_out'] ?? stats['txBytes']);
        if (_lastTickRx != null && _lastTickTx != null && (rx > _lastTickRx! || tx > _lastTickTx!)) {
          final delta = (rx - _lastTickRx!) + (tx - _lastTickTx!);
          if (delta > 0) {
            await _ref.read(dataUsageControllerProvider.notifier).addUsageBytes(delta);
          }
        }
        _lastTickRx = rx;
        _lastTickTx = tx;
      } catch (_) {}
      final usage = _ref.read(dataUsageControllerProvider);
      if (usage.limitExceeded) {
        await _forceDisconnect(clearPrefs: true, markExpired: false);
        _setError(ecTrafficLimited, details: _dataLimitMessage, displayMessage: _dataLimitMessage);
        return;
      }
      final refreshedPolicy = _ref.read(authControllerProvider).session?.trafficPolicy;
      if (refreshedPolicy?.overQuota == true) {
        await _forceDisconnect(clearPrefs: true, markExpired: false);
        _setError(ecTrafficLimited, details: _dataLimitMessage, displayMessage: _dataLimitMessage);
        return;
      }
      final server = _currentServer;
      if (server != null && (_tickCounter == 1 || _tickCounter % 8 == 0)) {
        await _notificationService.updateSession(
          server: server,
          remaining: remaining,
          state: state,
        );
      }
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
    _lastTickRx = null;
    _lastTickTx = null;
    _tickCounter = 0;
  }



  Future<void> autoConnectIfEnabled({required BuildContext context}) async {
    if (!_pendingAutoConnect) return;
    _pendingAutoConnect = false;
    final settings = _ref.read(settingsControllerProvider);
    if (!settings.autoConnect.connectOnLaunch) {
      return;
    }
    final server = _ref.read(selectedServerProvider);
    if (server == null) {
      return;
    }
    if (state.status == SessionStatus.connected) {
      return;
    }
    await connect(context: context, server: server);
  }

  @override
  void dispose() {
    _cancelConnectionTimeout();
    _stopConnectivityWatch();
    _ticker?.cancel();
    _intentSubscription?.cancel();
    _stageSubscription?.cancel();
    _speedSubscription.close();
    _pendingConnection = null;
    _currentServer = null;
    unawaited(_notificationService.clear());
    super.dispose();
  }

  Future<void> switchServer(Server server) async {
    _queuedServer = server;
    if (state.status != SessionStatus.connected) {
      _applyQueuedServerSelection();
    }
  }

  /// 全屏游戏模式开关或减速偏好变化后，重连使隧道上的 shaper 与当前 overlay / 减速一致。
  Future<void> reconnectToApplyGameModeTunnel(BuildContext context) async {
    if (state.status != SessionStatus.connected) return;
    if (_manualDisconnectInProgress || _pendingConnection != null) {
      _log('reconnectToApplyGameModeTunnel skipped: operation in progress');
      return;
    }
    final server = _currentServer ?? _ref.read(selectedServerProvider);
    if (server == null) {
      _log('reconnectToApplyGameModeTunnel: no server');
      return;
    }
    _log('reconnectToApplyGameModeTunnel: ${server.name}');
    await disconnect(userInitiated: false);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (_manualDisconnectInProgress) return;
    await connect(
      context: context,
      server: server,
      fromSmartStableReconnect: true,
    );
  }

  /// 断开并立即用当前节点重连，使 SmartStable（tun-mtu / mssfix）等新配置生效。
  Future<void> reconnectForSmartStable(BuildContext context) async {
    if (state.status != SessionStatus.connected) return;
    if (_manualDisconnectInProgress || _pendingConnection != null) {
      _log('reconnectForSmartStable skipped: operation in progress');
      return;
    }
    final server = _currentServer ?? _ref.read(selectedServerProvider);
    if (server == null) {
      _log('reconnectForSmartStable: no server');
      return;
    }
    _log('reconnectForSmartStable: ${server.name}');
    _ref.read(smartStableProvider.notifier).armReconnectCooldown();
    await disconnect(userInitiated: false);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (_manualDisconnectInProgress) return;
    await connect(
      context: context,
      server: server,
      fromSmartStableReconnect: true,
    );
  }

  /// 直接切换节点：断开当前连接并连接到新节点
  Future<void> switchToServerAndConnect({
    required BuildContext context,
    required Server server,
  }) async {
    if (state.status == SessionStatus.connected && _currentServer?.id == server.id) {
      return;
    }
    if (_manualDisconnectInProgress || _pendingConnection != null) {
      _log('Ignoring switch: operation in progress');
      return;
    }
    _log('switchToServerAndConnect: ${server.name}');
    if (state.status == SessionStatus.connected) {
      await disconnect(userInitiated: false);
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    if (_manualDisconnectInProgress) return;
    _ref.read(selectedServerProvider.notifier).select(server);
    await connect(context: context, server: server);
  }
}

final sessionControllerProvider =
    StateNotifierProvider<SessionController, SessionState>((ref) {
  return SessionController(ref);
});

class _PendingConnection {
  const _PendingConnection({
    required this.server,
    required this.startElapsedMs,
    required this.initialIp,
  });

  final Server server;
  final int startElapsedMs;
  final String? initialIp;
}
