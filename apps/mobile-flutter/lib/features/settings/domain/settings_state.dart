import 'package:equatable/equatable.dart';

import 'auto_connect_rules.dart';
import 'log_config.dart';
import 'protocol_config.dart';
import 'routing_config.dart';
import 'split_tunnel_config.dart';
import 'advanced_settings_config.dart';

class SettingsState extends Equatable {
  const SettingsState({
    this.protocol = const ProtocolConfig(),
    this.splitTunnel = const SplitTunnelConfig(),
    this.advanced = const AdvancedSettingsConfig(),
    this.routing = const RoutingConfig(),
    this.logConfig = const LogConfig(),
    this.autoConnect = const AutoConnectRules(),
    this.batterySaverEnabled = false,
    this.networkQualityMonitoring = true,
    this.preciseSessionTimer = false,
    this.darkMode = false,
    this.accentSeed = 'ocean',
    this.autoUpdateChecks = true,
  });

  final ProtocolConfig protocol;
  final SplitTunnelConfig splitTunnel;
  final AdvancedSettingsConfig advanced;
  final RoutingConfig routing;
  final LogConfig logConfig;
  final AutoConnectRules autoConnect;
  final bool batterySaverEnabled;
  final bool networkQualityMonitoring;
  final bool preciseSessionTimer;
  final bool darkMode;
  final String accentSeed;
  final bool autoUpdateChecks;

  SettingsState copyWith({
    ProtocolConfig? protocol,
    SplitTunnelConfig? splitTunnel,
    AdvancedSettingsConfig? advanced,
    RoutingConfig? routing,
    LogConfig? logConfig,
    AutoConnectRules? autoConnect,
    bool? batterySaverEnabled,
    bool? networkQualityMonitoring,
    bool? preciseSessionTimer,
    bool? darkMode,
    String? accentSeed,
    bool? autoUpdateChecks,
  }) {
    return SettingsState(
      protocol: protocol ?? this.protocol,
      splitTunnel: splitTunnel ?? this.splitTunnel,
      advanced: advanced ?? this.advanced,
      routing: routing ?? this.routing,
      logConfig: logConfig ?? this.logConfig,
      autoConnect: autoConnect ?? this.autoConnect,
      batterySaverEnabled: batterySaverEnabled ?? this.batterySaverEnabled,
      networkQualityMonitoring:
          networkQualityMonitoring ?? this.networkQualityMonitoring,
      preciseSessionTimer: preciseSessionTimer ?? this.preciseSessionTimer,
      darkMode: darkMode ?? this.darkMode,
      accentSeed: accentSeed ?? this.accentSeed,
      autoUpdateChecks: autoUpdateChecks ?? this.autoUpdateChecks,
    );
  }

  @override
  List<Object?> get props => [
        protocol,
        splitTunnel,
        advanced,
        routing,
        logConfig,
        autoConnect,
        batterySaverEnabled,
        networkQualityMonitoring,
        preciseSessionTimer,
        darkMode,
        accentSeed,
        autoUpdateChecks,
      ];
}
