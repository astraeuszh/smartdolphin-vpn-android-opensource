import 'package:equatable/equatable.dart';

import 'traffic_mode.dart';

/// Routing/tunnel configuration persisted and used by OpenVPN.
class RoutingConfig extends Equatable {
  const RoutingConfig({
    this.mode = TrafficMode.auto,
    this.autoRouteSystem = true,
    this.bypassLan = true,
    this.ruleDb = const RuleDatabase(),
  });

  final TrafficMode mode;
  /// When true, route all system traffic through VPN (redirect-gateway).
  /// When false, remove redirect-gateway so only explicit routes go through VPN.
  final bool autoRouteSystem;
  final bool bypassLan;
  final RuleDatabase ruleDb;

  RoutingConfig copyWith({
    TrafficMode? mode,
    bool? autoRouteSystem,
    bool? bypassLan,
    RuleDatabase? ruleDb,
  }) =>
      RoutingConfig(
        mode: mode ?? this.mode,
        autoRouteSystem: autoRouteSystem ?? this.autoRouteSystem,
        bypassLan: bypassLan ?? this.bypassLan,
        ruleDb: ruleDb ?? this.ruleDb,
      );

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'autoRouteSystem': autoRouteSystem,
        'bypassLan': bypassLan,
        'ruleDb': ruleDb.toJson(),
      };

  factory RoutingConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const RoutingConfig();
    return RoutingConfig(
      mode: TrafficMode.values.firstWhere(
        (m) => m.name == json['mode'],
        orElse: () => TrafficMode.auto,
      ),
      autoRouteSystem: json['autoRouteSystem'] as bool? ?? true,
      bypassLan: json['bypassLan'] as bool? ?? true,
      ruleDb: RuleDatabase.fromJson(json['ruleDb'] as Map<String, dynamic>?),
    );
  }

  @override
  List<Object?> get props => [mode, autoRouteSystem, bypassLan, ruleDb];
}
