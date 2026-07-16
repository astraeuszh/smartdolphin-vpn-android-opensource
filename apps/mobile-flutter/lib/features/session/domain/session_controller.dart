import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/vpn/vpn_stage.dart';

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
import '../../../services/remote/console_traffic.dart';
import '../../../services/remote/console_audit.dart';
import '../../../services/logging/error_reporter.dart';
import '../../../services/logging/vpn_logger.dart';
import '../../../services/vpn/clash_api_client.dart';
import '../../../services/vpn/dolphin_core_port.dart';
import '../../../services/vpn/node_table.dart';
import '../../../services/vpn/proxy_share_service.dart';
import '../../../services/vpn/vpn_provider.dart';
import '../../../services/vpn/models/vpn.dart';
import '../../settings/domain/preferences_controller.dart';
import '../../servers/data/static_servers.dart';
import '../../servers/domain/server.dart';
import '../../servers/domain/server_providers.dart';
import '../../settings/domain/advanced_settings_config.dart';
import '../../settings/domain/settings_controller.dart';
import '../../settings/domain/split_tunnel_config.dart';
import '../../settings/domain/traffic_mode.dart';
import '../../settings/domain/vpn_protocol.dart';
import '../../../services/apps/installed_apps_service.dart';
import '../../speedtest/domain/speedtest_controller.dart';
import '../../speedtest/domain/speedtest_state.dart';
import '../../dashboard/domain/ip_info_provider.dart';
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
const _dataLimitMessage =
    'Monthly data quota is exhausted. Try again next month or contact an administrator.';
const _violationThrottleMessage =
    'This account has traffic limits due to community rule violations. Please follow the community rules.';
const _connectionTimeoutDuration = Duration(seconds: 30);

class SessionController extends StateNotifier<SessionState> {
  SessionController(this._ref)
      : _vpnPort = _ref.read(openVpnPortProvider),
        _clock = _ref.read(sessionClockProvider),
        _settings = _ref.read(settingsControllerProvider.notifier),
        _vpnLogger = _ref.read(vpnLoggerProvider),
        _notificationService = _ref.read(sessionNotificationServiceProvider),
        super(SessionState.initial()) {
    _speedSubscription = _ref.listen<SpeedTestState>(
        speedTestControllerProvider, _onSpeedUpdate);
    // Web: flutter_local_notifications initialize() may never complete; skip.
    if (!kIsWeb) {
      unawaited(
        _notificationService.initialize(onAction: _handleNotificationAction),
      );
    }
    _stageSubscription = _vpnPort.stageStream.listen((stage) {
      unawaited(_handleVpnStage(stage));
    });
    _ref.listen<AuthState>(authControllerProvider, (_, __) {
      unawaited(_applyAccountTrafficPolicyFromServer());
    });
    _bootstrap();
  }

  final Ref _ref;
  final DolphinCorePort _vpnPort;
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
  int _bytesSinceTrafficReport = 0;
  bool _networkWasLost = false;
  bool? _appliedAccountThrottle;
  bool _accountTrafficReconnectBusy = false;
  int _tunnelHealthFailures = 0;
  bool _tunnelHealthReconnectBusy = false;
  bool _reconnectInProgress = false;

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

  void _setError(int code,
      {String? details, Object? cause, String? displayMessage}) {
    final wasConnected = state.status == SessionStatus.connected;
    final wasConnecting = state.status == SessionStatus.connecting ||
        state.status == SessionStatus.preparing;
    final err = AppError(code,
        details: details ?? '', cause: cause, displayMessage: displayMessage);
    logAppError(err, 'SessionController');
    state = state.copyWith(
      status: SessionStatus.error,
      errorMessage: err.message,
      errorCode: code,
    );
    if (wasConnected || wasConnecting || _pendingConnection != null) {
      unawaited(_reportAudit(
          'vpn_error', {'error_code': code, 'reason': details ?? ''}));
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
      _log(
          'Connection timed out after ${_connectionTimeoutDuration.inSeconds}s');
      _stopConnectivityWatch();
      final pending = _pendingConnection;
      _pendingConnection = null;
      _setError(ecNodeConnTimeout,
          details: 'timeout ${_connectionTimeoutDuration.inSeconds}s');
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
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((results) {
      final hasNetwork = results.isNotEmpty &&
          !results.every((r) => r == ConnectivityResult.none);
      if (!hasNetwork) {
        _networkWasLost = true;
        if (state.status == SessionStatus.connecting &&
            _pendingConnection != null) {
          _log('Network lost during connection');
          _abortConnectionForNetworkLost();
        }
        return;
      }
      if (_networkWasLost &&
          _ref
              .read(settingsControllerProvider)
              .autoConnect
              .reconnectOnNetworkChange) {
        _networkWasLost = false;
        final server = _currentServer;
        if (server != null &&
            state.status != SessionStatus.connected &&
            state.status != SessionStatus.connecting &&
            !_manualDisconnectInProgress) {
          _log('Network restored; attempting reconnect to ${server.name}');
          unawaited(_tryAutoReconnect(server));
        }
      }
    });
  }

  void _stopConnectivityWatch() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
  }

  void _abortConnectionForNetworkLost() {
    if (state.status != SessionStatus.connecting || _pendingConnection == null)
      return;
    _cancelConnectionTimeout();
    _stopConnectivityWatch();
    final pending = _pendingConnection;
    _pendingConnection = null;
    unawaited(_notificationService.clear());
    _setError(ecLocalNetDisconnected, details: 'network lost');
    unawaited(_vpnPort.disconnect());
  }

  Future<void> _bootstrap() async {
    _pendingAutoConnect = true;
    _intentSubscription = _vpnPort.intentActions.listen(_handleIntentAction);
    await _ref.read(preferencesControllerProvider.notifier).ready;
    await _ref.read(settingsControllerProvider.notifier).profileMigrationReady;
    await _restoreSession();
    unawaited(_reportAudit('app_open'));
    await _reconnectAfterProfileMigrationIfNeeded();
  }

  /// After OTA profile migration the native BoxService may still run the old
  /// VLESS/global config while prefs already say Hysteria2 + smart split.
  Future<void> _reconnectAfterProfileMigrationIfNeeded() async {
    if (!isAndroidNative) return;
    final prefs = await _ref.read(prefsStoreProvider.future);
    if (prefs.getBool(androidTunnelReconnectPrefKey) != true) return;
    await prefs.remove(androidTunnelReconnectPrefKey);

    final server = _resolveHistoryServer();
    if (server == null) {
      _log('Profile migration reconnect skipped: no server');
      return;
    }
    final nativeUp = await _vpnPort.isConnected();
    if (!nativeUp && state.status != SessionStatus.connected) {
      return;
    }
    _log('Profile migration: reconnecting with current protocol + smart split');
    _currentServer = server;
    await disconnect(userInitiated: false);
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (_manualDisconnectInProgress) return;
    await connect(server: server);
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
          _log(
              'Ignoring disconnected (teardown of previous session) during connect');
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
    unawaited(_reportAudit('vpn_connect', _auditNodeMetadata(server)));
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
    _tunnelHealthFailures = 0;
    _tunnelHealthReconnectBusy = false;
    if (isAndroidNative) {
      unawaited(setHasActiveSession(true));
    }
    final adv = _ref.read(settingsControllerProvider).advanced;
    unawaited(ProxyShareService.sync(
      vpnConnected: true,
      enabled: adv.proxyShareEnabled,
      mode: adv.proxyShareMode,
    ));

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
    _startConnectivityWatch();
    // The egress IP is only known AFTER the tunnel is up, so refresh it through
    // the VPN (the pre-connect IP captured above is the local one).
    unawaited(_refreshPublicIpAfterConnect());
  }

  /// Fetches the public IP through the live tunnel and updates the dashboard so
  /// it shows the VPN exit IP (not the local pre-connect IP).
  Future<void> _refreshPublicIpAfterConnect() async {
    await Future<void>.delayed(const Duration(seconds: 2));
    if (state.status != SessionStatus.connected) return;
    try {
      final info = await fetchIpInfo();
      if (state.status != SessionStatus.connected) return;
      final ip = info.ip;
      if (ip != null && ip.isNotEmpty) {
        _activeMeta = _activeMeta?.copyWith(publicIp: ip);
        state = state.copyWith(publicIp: ip, meta: _activeMeta);
      }
      _ref.invalidate(ipInfoProvider);
    } catch (_) {
      // best-effort; dashboard keeps the last known IP
    }
  }

  Future<void> _handleRemoteDisconnect() async {
    final server = _currentServer;
    final killSwitch =
        _ref.read(settingsControllerProvider).advanced.killSwitchMode;
    if (server != null &&
        _ref
            .read(settingsControllerProvider)
            .autoConnect
            .reconnectOnNetworkChange) {
      _log(
          'Unexpected disconnect; attempting auto-reconnect to ${server.name}');
      await _tryAutoReconnect(server);
      return;
    }
    if (killSwitch != KillSwitchMode.off && isAndroidNative) {
      unawaited(_notificationService.showKillSwitchAlert());
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
    if (_reconnectInProgress) {
      _log('Auto-reconnect skipped: another reconnect is active');
      return;
    }
    _reconnectInProgress = true;
    try {
      for (var i = 0; i < _reconnectDelays.length; i++) {
        await Future<void>.delayed(_reconnectDelays[i]);
        if (state.status == SessionStatus.connected ||
            _manualDisconnectInProgress) {
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
    } finally {
      _reconnectInProgress = false;
    }
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
    // The server-side account check includes the Android 4.0.4 minimum build
    // gate. Run it before constructing a new protocol handshake so a client
    // that cannot meet the active service policy never starts a fresh tunnel.
    final authorized = await _ref
        .read(authControllerProvider.notifier)
        .ensureVpnAccess();
    if (!authorized) {
      _setError(
        ecCoreStartFailed,
        details: 'service authorization or minimum version rejected',
        displayMessage: 'A current SmartDolphin VPN version and active account are required.',
      );
      return;
    }
    final trafficPolicy =
        _ref.read(authControllerProvider).session?.trafficPolicy;
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
      _ref
          .read(smartStableProvider.notifier)
          .clearDeclineSuppressForNewUserConnect();
    }
    final routing = _ref.read(settingsControllerProvider).routing;
    if (routing.mode == TrafficMode.rule) {
      final hasRules =
          routing.ruleDb.customRules.split(RegExp(r'\r?\n')).any((line) {
        final t = line.trim();
        return t.isNotEmpty && !t.startsWith('#');
      });
      if (!hasRules) {
        _setError(
          ecNodeConfigFailed,
          details: 'rule mode empty',
          displayMessage: 'Rule mode requires at least one split-routing rule.',
        );
        return;
      }
    }
    if (state.status == SessionStatus.connected) {
      _log('Hard reconnect: tearing down existing Dolphin-Core tunnel first');
      await disconnect(userInitiated: false);
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }
    // Prevent double-connect: if we're already connecting to the same server,
    // ignore. A second connect() would call disconnect() first (in dolphin_core_port)
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
    // Show the connecting state immediately so the UI responds to the tap.
    state = state.copyWith(
      status: SessionStatus.connecting,
      errorMessage: null,
    );
    await Future<void>.delayed(
        Duration.zero); // yield so UI paints orange immediately

    // Check local connectivity before starting the tunnel.
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

    // Request VPN permission with a timeout. Some Android builds can leave
    // prepare() hanging after long background sessions.
    final prepared = await _vpnPort
        .prepare()
        .timeout(const Duration(seconds: 12), onTimeout: () => false);
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
      final tp = _ref.read(authControllerProvider).session?.trafficPolicy;
      final wantThrottle = tp?.isViolationSpeedLimit == true;
      _vpnPort.setAccountTrafficThrottle(wantThrottle);
      _appliedAccountThrottle = wantThrottle;
      _vpnPort.setGameTrafficMode(_ref.read(gameModeControllerProvider));
      _vpnPort.setGameDecelTier(_ref.read(gameDecelTierProvider));
      _vpnPort
          .setGameModeOverlayActive(_ref.read(gameModeOverlayActiveProvider));

      var routing = settingsState.routing;
      final advanced = settingsState.advanced;
      if (advanced.tunnelMode == TunnelInterfaceMode.systemProxy) {
        routing = routing.copyWith(autoRouteSystem: false);
      } else if (routing.mode == TrafficMode.global) {
        routing = routing.copyWith(autoRouteSystem: true);
      }
      _vpnPort.setAdvancedConfig(advanced);
      _vpnPort.setRoutingConfig(routing);
      final coreProto = _ref.read(preferencesControllerProvider).coreProtocol;
      _vpnPort.setProtocol(sdProtocolFromName(coreProto));
      final node = nodeForHostOrCountry(server.ip, server.countryName);
      _log(
          'Dolphin-Core: protocol=$coreProto node=${node.tag} host=${node.host}');
      _vpnPort.setDnsServers(settingsState.protocol.resolvedDnsServers);
      _vpnPort.setSplitTunnel(
        settingsState.splitTunnel.mode,
        settingsState.splitTunnel.selectedPackages.toList(),
      );
      final initialIp = _ref.read(speedTestControllerProvider).ip;
      final startElapsed = await _clock.elapsedRealtime();

      // Prefer the bundled SmartDolphin node config over cached catalog data.
      final configBase64 = _resolveConfigBase64(server);

      // Convert Server to Vpn model for Dolphin-Core connection
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
        _log('Missing node config for server ${server.id}');
        _setError(ecNodeConfigFailed,
            details: 'No config for server ${server.id}');
        return;
      }

      try {
        final decodedConfig = vpnServer.openVpnConfig;
        if (decodedConfig.trim().isEmpty) {
          _log('Missing node config for server ${server.id}');
          _setError(ecNodeConfigFailed, details: 'Empty config');
          return;
        }
      } on AppError catch (error) {
        _log('Invalid node config for server ${server.id}: $error');
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

      _log(
          'Attempting to connect to VPN server: ${vpnServer.hostName}, IP: ${vpnServer.ip}');
      _log('Config length: ${vpnServer.openVpnConfig.length}');

      final connected = await _vpnPort.connect(vpnServer);
      _log('Dolphin-Core connect() returned $connected');
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
    _log(
        'disconnect() requested. Status: ${state.status}, userInitiated: $userInitiated');
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
      if (wasConnected) {
        final server = _resolveHistoryServer(fromState: previousState);
        unawaited(_reportAudit('vpn_disconnect', {
          ..._auditNodeMetadata(server),
          'reason': userInitiated ? 'user' : 'system',
          'session_seconds': previousState.start == null
              ? 0
              : DateTime.now()
                  .toUtc()
                  .difference(previousState.start!)
                  .inSeconds
                  .clamp(0, 86400),
        }));
      }

      // Reset UI state FIRST so user sees disconnect immediately (avoids crash blocking UI)
      _activeMeta = null;
      _currentServer = null;
      state = SessionState.initial();
      if (isAndroidNative) {
        unawaited(setHasActiveSession(false));
      }
      _applyQueuedServerSelection();

      // Tear down VPN and notification in background. A bounded timeout is critical: after the OS
      // reclaims the VPN service during long background, a native call can hang forever; without a
      // timeout the `finally` below never runs, _manualDisconnectInProgress stays true, and every
      // later tap (connect/switch/disconnect) is silently ignored; the UI looks frozen until the
      // app is force-killed.
      try {
        await _vpnPort
            .disconnect()
            .timeout(const Duration(seconds: 6), onTimeout: () {});
      } catch (e) {
        _log('disconnect: VPN tear-down error (ignored): $e');
      }
      unawaited(ProxyShareService.sync(
        vpnConnected: false,
        enabled: false,
        mode: ProxyShareMode.http,
      ));
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
            stats.addAll(await _vpnPort.getTunnelStats().timeout(
                const Duration(seconds: 4),
                onTimeout: () => <String, dynamic>{}));
          } catch (_) {}
          Duration? actualDuration;
          if (meta != null) {
            try {
              final nowMs = await _clock.elapsedRealtime().timeout(
                  const Duration(seconds: 4),
                  onTimeout: () => meta.startElapsedMs);
              actualDuration = Duration(
                  milliseconds: (nowMs - meta.startElapsedMs)
                      .clamp(0, meta.durationMs)
                      .toInt());
            } catch (_) {}
          }
          final sessionForHistory = actualDuration != null
              ? previousState.copyWith(duration: actualDuration)
              : previousState;
          await _settings
              .recordSessionEnd(sessionForHistory, server: server, stats: stats)
              .timeout(const Duration(seconds: 6), onTimeout: () {});
          await _clearPersistedState()
              .timeout(const Duration(seconds: 4), onTimeout: () {});
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
    await _vpnPort
        .disconnect()
        .timeout(const Duration(seconds: 6), onTimeout: () {});
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
      state = SessionState.initial()
          .copyWith(expired: markExpired, sessionLocked: false);
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
    // Session expiry and quota accounting do not need UI-frame cadence. A
    // 30-second batch avoids repeatedly waking Flutter + libbox in background.
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) async {
      _tickCounter += 1;
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
          displayMessage:
              'The current service has an error. Please restart this service.',
        );
        return;
      }
      try {
        final stats = await _vpnPort.getTunnelStats();
        final rx = _parseBytes(stats['byte_in'] ?? stats['rxBytes']);
        final tx = _parseBytes(stats['byte_out'] ?? stats['txBytes']);
        if (_lastTickRx != null &&
            _lastTickTx != null &&
            (rx > _lastTickRx! || tx > _lastTickTx!)) {
          final delta = (rx - _lastTickRx!) + (tx - _lastTickTx!);
          if (delta > 0) {
            await _ref
                .read(dataUsageControllerProvider.notifier)
                .addUsageBytes(delta);
            _bytesSinceTrafficReport += delta;
          }
        }
        _lastTickRx = rx;
        _lastTickTx = tx;
      } catch (_) {}
      if (_tickCounter % 4 == 0) {
        unawaited(_ref.read(authControllerProvider.notifier).refreshSession());
      }
      if (_tickCounter % 10 == 0 && _bytesSinceTrafficReport > 0) {
        final session = _ref.read(authControllerProvider).session;
        if (session != null) {
          final reportBytes = _bytesSinceTrafficReport;
          _bytesSinceTrafficReport = 0;
          unawaited(() async {
            try {
              await ConsoleTraffic()
                  .reportBytes(session: session, bytes: reportBytes);
              await _ref.read(authControllerProvider.notifier).refreshSession();
              await _applyAccountTrafficPolicyFromServer();
            } catch (_) {}
          }());
        }
      }
      if (_tickCounter % 10 == 0) {
        final server = _currentServer;
        if (server != null) {
          final stats = await _vpnPort.getTunnelStats();
          unawaited(_reportAudit('traffic_snapshot', {
            ..._auditNodeMetadata(server),
            'rx_bytes': _parseBytes(stats['byte_in'] ?? stats['rxBytes']),
            'tx_bytes': _parseBytes(stats['byte_out'] ?? stats['txBytes']),
          }));
        }
      }
      final usage = _ref.read(dataUsageControllerProvider);
      if (usage.limitExceeded) {
        await _forceDisconnect(clearPrefs: true, markExpired: false);
        _setError(ecTrafficLimited,
            details: _dataLimitMessage, displayMessage: _dataLimitMessage);
        return;
      }
      final refreshedPolicy =
          _ref.read(authControllerProvider).session?.trafficPolicy;
      if (refreshedPolicy?.overQuota == true) {
        await _forceDisconnect(clearPrefs: true, markExpired: false);
        _setError(ecTrafficLimited,
            details: _dataLimitMessage, displayMessage: _dataLimitMessage);
        return;
      }
      final server = _currentServer;
      if (server != null && (_tickCounter == 1 || _tickCounter % 2 == 0)) {
        await _notificationService.updateSession(
          server: server,
          remaining: remaining,
          state: state,
        );
      }
      // Every ~5 minutes, check whether the local core API is still alive.
      if (_tickCounter % 10 == 0) {
        unawaited(_evaluateTunnelHealth());
      }
    });
  }

  Future<void> _reportAudit(String event,
      [Map<String, dynamic> metadata = const {}]) async {
    final session = _ref.read(authControllerProvider).session;
    if (session == null) return;
    try {
      await ConsoleAudit().report(session, event: event, metadata: metadata);
    } catch (_) {}
  }

  Map<String, dynamic> _auditNodeMetadata(Server? server) {
    final protocol = _ref.read(preferencesControllerProvider).coreProtocol;
    return {
      'node_id': server?.id ?? '',
      'node_name': server?.name ?? '',
      'node_country': server?.countryCode ?? '',
      'protocol': protocol,
      'transport':
          protocol == 'hysteria2' || protocol == 'wireguard' ? 'udp' : 'tcp',
    };
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
    _lastTickRx = null;
    _lastTickTx = null;
    _tickCounter = 0;
    _tunnelHealthFailures = 0;
  }

  /// After long background, verify the tunnel still carries traffic; reconnect if dead.
  Future<void> checkTunnelHealthOnResume() async {
    if (state.status != SessionStatus.connected) return;
    if (_manualDisconnectInProgress || _pendingConnection != null) return;
    _log('Tunnel health check on app resume');
    await _evaluateTunnelHealth(resumeTriggered: true);
  }

  Future<void> _evaluateTunnelHealth({bool resumeTriggered = false}) async {
    if (_tunnelHealthReconnectBusy ||
        _accountTrafficReconnectBusy ||
        _manualDisconnectInProgress ||
        _pendingConnection != null) {
      return;
    }
    if (state.status != SessionStatus.connected) return;
    final server = _currentServer;
    if (server == null) return;

    final apiUp = await ClashApiClient.isAvailable();
    int? delay;
    if (apiUp) {
      delay = await ClashApiClient.proxyDelayMs(
        timeoutMs: resumeTriggered ? 5000 : 3500,
      );
    }
    final healthy = apiUp && delay != null;

    if (healthy) {
      _tunnelHealthFailures = 0;
      return;
    }

    _tunnelHealthFailures++;
    _log(
      'Tunnel unhealthy (failures=$_tunnelHealthFailures, api=$apiUp, delay=$delay)',
    );

    if (_tunnelHealthFailures < 3) return;
    await _hardReconnectForDeadTunnel(server);
  }

  Future<void> _hardReconnectForDeadTunnel(Server server) async {
    if (_tunnelHealthReconnectBusy || _reconnectInProgress) return;
    _tunnelHealthReconnectBusy = true;
    _reconnectInProgress = true;
    _tunnelHealthFailures = 0;
    try {
      _log('Dead tunnel detected; hard reconnect to ${server.name}');
      await disconnect(userInitiated: false);
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (_manualDisconnectInProgress) return;
      await connect(server: server, fromSmartStableReconnect: true);
    } finally {
      _tunnelHealthReconnectBusy = false;
      _reconnectInProgress = false;
    }
  }

  Future<void> autoConnectIfEnabled({
    required BuildContext context,
    bool fromBoot = false,
  }) async {
    if (!_pendingAutoConnect) return;
    _pendingAutoConnect = false;
    final settings = _ref.read(settingsControllerProvider);
    final ac = settings.autoConnect;
    final shouldConnect = ac.connectOnLaunch || (fromBoot && ac.connectOnBoot);
    if (!shouldConnect) {
      return;
    }
    Server? server;
    for (var i = 0; i < 20; i++) {
      server = _ref.read(selectedServerProvider);
      if (server != null) break;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
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

  /// Reconnect so server-side account speed throttling takes effect.
  Future<void> reconnectToApplyAccountTrafficPolicy() async {
    if (state.status != SessionStatus.connected) return;
    if (_manualDisconnectInProgress ||
        _pendingConnection != null ||
        _accountTrafficReconnectBusy ||
        _reconnectInProgress) {
      _log(
          'reconnectToApplyAccountTrafficPolicy skipped: operation in progress');
      return;
    }
    final server = _currentServer ?? _ref.read(selectedServerProvider);
    if (server == null) {
      _log('reconnectToApplyAccountTrafficPolicy: no server');
      return;
    }
    _accountTrafficReconnectBusy = true;
    _reconnectInProgress = true;
    try {
      _log('reconnectToApplyAccountTrafficPolicy: ${server.name}');
      await disconnect(userInitiated: false);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (_manualDisconnectInProgress) return;
      await connect(
        server: server,
        fromSmartStableReconnect: true,
      );
    } finally {
      _accountTrafficReconnectBusy = false;
      _reconnectInProgress = false;
    }
  }

  Future<void> _applyAccountTrafficPolicyFromServer() async {
    final tp = _ref.read(authControllerProvider).session?.trafficPolicy;
    final want = tp?.isViolationSpeedLimit == true;
    if (_appliedAccountThrottle == want) {
      _vpnPort.setAccountTrafficThrottle(want);
      return;
    }
    _log(
        'Account traffic throttle changed ($_appliedAccountThrottle -> $want)');
    _appliedAccountThrottle = want;
    _vpnPort.setAccountTrafficThrottle(want);
    if (state.status == SessionStatus.connected) {
      await reconnectToApplyAccountTrafficPolicy();
    }
  }

  /// Reconnect so the tunnel shaper matches the current game-mode settings.
  Future<void> reconnectToApplyGameModeTunnel(BuildContext context) async {
    if (state.status != SessionStatus.connected) return;
    if (_manualDisconnectInProgress ||
        _pendingConnection != null ||
        _reconnectInProgress) {
      _log('reconnectToApplyGameModeTunnel skipped: operation in progress');
      return;
    }
    final server = _currentServer ?? _ref.read(selectedServerProvider);
    if (server == null) {
      _log('reconnectToApplyGameModeTunnel: no server');
      return;
    }
    _log('reconnectToApplyGameModeTunnel: ${server.name}');
    _reconnectInProgress = true;
    try {
      await disconnect(userInitiated: false);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (_manualDisconnectInProgress) return;
      await connect(
        context: context,
        server: server,
        fromSmartStableReconnect: true,
      );
    } finally {
      _reconnectInProgress = false;
    }
  }

  /// Reconnect with the current server so SmartStable tuning takes effect.
  Future<void> reconnectForSmartStable(BuildContext context) async {
    if (state.status != SessionStatus.connected) return;
    if (_manualDisconnectInProgress ||
        _pendingConnection != null ||
        _reconnectInProgress) {
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
    _reconnectInProgress = true;
    try {
      await disconnect(userInitiated: false);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (_manualDisconnectInProgress) return;
      await connect(
        context: context,
        server: server,
        fromSmartStableReconnect: true,
      );
    } finally {
      _reconnectInProgress = false;
    }
  }

  /// Switch server by disconnecting the current tunnel and connecting again.
  Future<void> switchToServerAndConnect({
    required BuildContext context,
    required Server server,
  }) async {
    if (state.status == SessionStatus.connected &&
        _currentServer?.id == server.id) {
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

  Future<List<String>> _resolveBypassPackages(SplitTunnelConfig split) async {
    if (split.mode == SplitTunnelMode.allTraffic) {
      return const [];
    }
    if (split.mode == SplitTunnelMode.excludeApps) {
      return split.selectedPackages.toList();
    }
    if (split.selectedPackages.isEmpty) {
      return const [];
    }
    try {
      final apps = await InstalledAppsService().fetchInstalledApps();
      return apps
          .map((a) => a.packageName)
          .where((pkg) => !split.selectedPackages.contains(pkg))
          .toList();
    } catch (e) {
      _log('Failed to resolve include-app bypass list: $e');
      return const [];
    }
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
