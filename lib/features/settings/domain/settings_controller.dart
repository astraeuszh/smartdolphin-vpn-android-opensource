import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/runtime_platform.dart';
import '../../../platform/android/background_keep_alive.dart';
import '../../history/domain/connection_history_notifier.dart';
import '../../history/domain/connection_record.dart';
import '../../servers/domain/server.dart';
import '../../session/domain/session_state.dart';
import 'auto_connect_rules.dart';
import 'advanced_settings_config.dart';
import 'log_config.dart';
import 'protocol_config.dart';
import 'routing_config.dart';
import 'traffic_mode.dart';
import 'settings_state.dart';
import 'split_tunnel_config.dart';
import '../data/settings_repository.dart';
import 'vpn_protocol.dart';

class SettingsController extends StateNotifier<SettingsState> {
  SettingsController(this._ref, this._repository)
      : super(const SettingsState()) {
    _restore();
  }

  final Ref _ref;
  final SettingsRepository? _repository;

  Future<void> _restore() async {
    if (_repository == null) return;
    final protocol = _repository!.loadProtocol();
    final splitTunnel = _repository!.loadSplitTunnel();
    final advanced = _repository!.loadAdvanced();
    final routing = _repository!.loadRouting();
    final logConfig = _repository!.loadLog();
    final autoConnect = _repository!.loadAutoConnect();
    final batterySaver = _repository!.loadBatterySaver();
    final networkQuality = _repository!.loadNetworkQuality();
    final preciseSessionTimer = _repository!.loadPreciseSessionTimer();
    final storedAccent = _repository!.loadAccent() ?? 'ocean';
    final accent = storedAccent == 'lavender' ? 'ocean' : storedAccent;
    state = state.copyWith(
      protocol: protocol,
      splitTunnel: splitTunnel,
      advanced: advanced,
      routing: routing,
      logConfig: logConfig,
      autoConnect: autoConnect,
      batterySaverEnabled: batterySaver,
      networkQualityMonitoring: networkQuality,
      preciseSessionTimer: preciseSessionTimer,
      accentSeed: accent,
    );
    if (isAndroidNative) {
      unawaited(setWakeOnBootEnabled(
        autoConnect.connectOnLaunch || autoConnect.connectOnBoot,
      ));
    }
  }

  Future<void> updateProtocol(ProtocolConfig config) async {
    state = state.copyWith(protocol: config);
    await _repository?.saveProtocol(config);
  }

  Future<void> setProtocol(VpnProtocol protocol) =>
      updateProtocol(state.protocol.copyWith(protocol: protocol));

  Future<void> setMtu(int mtu) =>
      updateProtocol(state.protocol.copyWith(mtu: mtu));

  Future<void> setKeepalive(int seconds) =>
      updateProtocol(state.protocol.copyWith(keepaliveSeconds: seconds));

  Future<void> setDnsOption(VpnDnsOption option) async {
    await updateProtocol(state.protocol.copyWith(dnsOption: option));
  }

  Future<void> updateAdvanced(AdvancedSettingsConfig config) async {
    state = state.copyWith(advanced: config);
    await _repository?.saveAdvanced(config);
  }

  Future<void> setKillSwitchMode(KillSwitchMode mode) async {
    await updateAdvanced(state.advanced.copyWith(killSwitchMode: mode));
  }

  Future<void> setForceDnsThroughTunnel(bool value) async {
    await updateAdvanced(state.advanced.copyWith(forceDnsThroughTunnel: value));
  }

  Future<void> setBlockLocalDns(bool value) async {
    await updateAdvanced(state.advanced.copyWith(blockLocalDns: value));
  }

  Future<void> setBlockIpv6Dns(bool value) async {
    await updateAdvanced(state.advanced.copyWith(blockIpv6Dns: value));
  }

  Future<void> setDisableIpv6WhenConnected(bool value) async {
    await updateAdvanced(state.advanced.copyWith(disableIpv6WhenConnected: value));
  }

  Future<void> setTransportProtocol(TransportProtocol protocol) async {
    await updateAdvanced(state.advanced.copyWith(transportProtocol: protocol));
  }

  Future<void> setTunnelInterfaceMode(TunnelInterfaceMode mode) async {
    await updateAdvanced(state.advanced.copyWith(tunnelMode: mode));
  }

  Future<void> setProxyShareEnabled(bool value) async {
    await updateAdvanced(state.advanced.copyWith(proxyShareEnabled: value));
  }

  Future<void> setProxyShareMode(ProxyShareMode mode) async {
    await updateAdvanced(state.advanced.copyWith(proxyShareMode: mode));
  }

  Future<void> updateSplitTunnel(SplitTunnelConfig config) async {
    state = state.copyWith(splitTunnel: config);
    await _repository?.saveSplitTunnel(config);
  }

  Future<void> updateRouting(RoutingConfig config) async {
    state = state.copyWith(routing: config);
    await _repository?.saveRouting(config);
  }

  Future<void> setTrafficMode(TrafficMode mode) async {
    await updateRouting(state.routing.copyWith(mode: mode));
  }

  Future<void> setAutoRouteSystem(bool value) async {
    await updateRouting(state.routing.copyWith(autoRouteSystem: value));
  }

  Future<void> setBypassLan(bool value) async {
    await updateRouting(state.routing.copyWith(bypassLan: value));
  }

  Future<void> setRuleSource(RuleSource source) async {
    await updateRouting(state.routing.copyWith(
      ruleDb: state.routing.ruleDb.copyWith(source: source),
    ));
  }

  Future<void> setCustomRules(String text) async {
    await updateRouting(state.routing.copyWith(
      ruleDb: state.routing.ruleDb.copyWith(customRules: text),
    ));
  }

  Future<void> updateLogConfig(LogConfig config) async {
    state = state.copyWith(logConfig: config);
    await _repository?.saveLog(config);
  }

  Future<void> setLogEnabled(bool value) async {
    await updateLogConfig(state.logConfig.copyWith(enabled: value));
  }

  Future<void> setLogLevel(String level) async {
    await updateLogConfig(state.logConfig.copyWith(level: level));
  }

  Future<void> setLogSizeLimitMb(int mb) async {
    await updateLogConfig(state.logConfig.copyWith(sizeLimitMb: mb));
  }

  Future<void> setLogCountLimit(int count) async {
    await updateLogConfig(state.logConfig.copyWith(countLimit: count));
  }

  Future<void> toggleSplitTunnel(bool enabled) async {
    final mode = enabled
        ? SplitTunnelMode.includeApps
        : SplitTunnelMode.allTraffic;
    await updateSplitTunnel(state.splitTunnel.copyWith(mode: mode));
  }

  Future<void> setAppSplitMode(SplitTunnelMode mode) async {
    await updateSplitTunnel(state.splitTunnel.copyWith(mode: mode));
  }

  Future<void> setSelectedPackages(Set<String> packages) async {
    await updateSplitTunnel(state.splitTunnel.copyWith(
      selectedPackages: packages,
    ));
  }

  Future<void> updateAutoConnect(AutoConnectRules rules) async {
    state = state.copyWith(autoConnect: rules);
    await _repository?.saveAutoConnect(rules);
  }

  Future<void> setAutoConnect({
    bool? onLaunch,
    bool? onBoot,
    bool? onNetworkChange,
  }) async {
    await updateAutoConnect(state.autoConnect.copyWith(
      connectOnLaunch: onLaunch,
      connectOnBoot: onBoot,
      reconnectOnNetworkChange: onNetworkChange,
    ));
  }

  Future<void> setBatterySaver(bool value) async {
    state = state.copyWith(batterySaverEnabled: value);
    await _repository?.saveBatterySaver(value);
  }

  Future<void> setNetworkQuality(bool value) async {
    state = state.copyWith(networkQualityMonitoring: value);
    await _repository?.saveNetworkQuality(value);
  }

  Future<void> setPreciseSessionTimer(bool value) async {
    state = state.copyWith(preciseSessionTimer: value);
    await _repository?.savePreciseSessionTimer(value);
  }

  Future<void> setAccentSeed(String seed) async {
    state = state.copyWith(accentSeed: seed);
    await _repository?.saveAccent(seed);
  }

  Future<void> recordSessionEnd(SessionState session,
      {required Server? server, required Map<String, dynamic> stats}) async {
    if (server == null) return;
    final history = _ref.read(connectionHistoryProvider.notifier);
    final startedAt = session.start!;
    final endedAt = DateTime.now().toUtc();
    final bytesRx = (stats['rxBytes'] as num?)?.toInt() ?? 0;
    final bytesTx = (stats['txBytes'] as num?)?.toInt() ?? 0;
    final duration = session.duration ?? endedAt.difference(startedAt);
    final locationParts = <String>[
      if (server.cityName != null && server.cityName!.isNotEmpty) server.cityName!,
      if (server.regionName != null && server.regionName!.isNotEmpty) server.regionName!,
      if (server.countryName != null && server.countryName!.isNotEmpty) server.countryName!,
    ];
    final location = locationParts.isEmpty ? null : locationParts.join(', ');

    await history.addRecord(
      ConnectionRecord(
        serverId: server.id,
        serverName: server.name,
        startedAt: startedAt,
        endedAt: endedAt,
        durationSeconds: duration.inSeconds,
        bytesReceived: bytesRx,
        bytesSent: bytesTx,
        publicIp: session.publicIp,
        serverIp: server.ip ?? server.hostName ?? server.endpoint,
        serverLocation: location,
        serverBandwidth: server.bandwidth,
        serverDownloadSpeed: server.downloadSpeed,
        serverUploadSpeed: server.uploadSpeed,
      ),
    );
  }
}

final settingsControllerProvider =
    StateNotifierProvider<SettingsController, SettingsState>((ref) {
  return SettingsController(
    ref,
    ref.watch(settingsRepositoryProvider),
  );
});
