import 'package:equatable/equatable.dart';

import 'package:smartdolphin_vpn/core/utils/iterable_extensions.dart';
import 'transport_profile.dart';

/// Kill Switch：VPN 断开时的断网策略（前端配置，待接入隧道层）。
enum KillSwitchMode { off, strict, smart }

/// 系统接管方式：TUN 全系统 / 系统代理部分程序。
enum TunnelInterfaceMode { tun, systemProxy }

/// 代理共享方式。
enum ProxyShareMode { http, socks5, lan }

class AdvancedSettingsConfig extends Equatable {
  const AdvancedSettingsConfig({
    this.killSwitchMode = KillSwitchMode.off,
    this.forceDnsThroughTunnel = true,
    this.blockLocalDns = true,
    this.blockIpv6Dns = false,
    this.disableIpv6WhenConnected = true,
    this.transportProtocol = TransportProtocol.openVpn,
    this.tunnelMode = TunnelInterfaceMode.tun,
    this.proxyShareEnabled = false,
    this.proxyShareMode = ProxyShareMode.http,
  });

  final KillSwitchMode killSwitchMode;
  final bool forceDnsThroughTunnel;
  final bool blockLocalDns;
  final bool blockIpv6Dns;
  final bool disableIpv6WhenConnected;
  final TransportProtocol transportProtocol;
  final TunnelInterfaceMode tunnelMode;
  final bool proxyShareEnabled;
  final ProxyShareMode proxyShareMode;

  AdvancedSettingsConfig copyWith({
    KillSwitchMode? killSwitchMode,
    bool? forceDnsThroughTunnel,
    bool? blockLocalDns,
    bool? blockIpv6Dns,
    bool? disableIpv6WhenConnected,
    TransportProtocol? transportProtocol,
    TunnelInterfaceMode? tunnelMode,
    bool? proxyShareEnabled,
    ProxyShareMode? proxyShareMode,
  }) {
    return AdvancedSettingsConfig(
      killSwitchMode: killSwitchMode ?? this.killSwitchMode,
      forceDnsThroughTunnel:
          forceDnsThroughTunnel ?? this.forceDnsThroughTunnel,
      blockLocalDns: blockLocalDns ?? this.blockLocalDns,
      blockIpv6Dns: blockIpv6Dns ?? this.blockIpv6Dns,
      disableIpv6WhenConnected:
          disableIpv6WhenConnected ?? this.disableIpv6WhenConnected,
      transportProtocol: transportProtocol ?? this.transportProtocol,
      tunnelMode: tunnelMode ?? this.tunnelMode,
      proxyShareEnabled: proxyShareEnabled ?? this.proxyShareEnabled,
      proxyShareMode: proxyShareMode ?? this.proxyShareMode,
    );
  }

  Map<String, dynamic> toJson() => {
        'killSwitchMode': killSwitchMode.name,
        'forceDnsThroughTunnel': forceDnsThroughTunnel,
        'blockLocalDns': blockLocalDns,
        'blockIpv6Dns': blockIpv6Dns,
        'disableIpv6WhenConnected': disableIpv6WhenConnected,
        'transportProtocol': transportProtocol.name,
        'tunnelMode': tunnelMode.name,
        'proxyShareEnabled': proxyShareEnabled,
        'proxyShareMode': proxyShareMode.name,
      };

  factory AdvancedSettingsConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const AdvancedSettingsConfig();
    return AdvancedSettingsConfig(
      killSwitchMode: killSwitchModeFromName(json['killSwitchMode'] as String?),
      forceDnsThroughTunnel: json['forceDnsThroughTunnel'] as bool? ?? true,
      blockLocalDns: json['blockLocalDns'] as bool? ?? true,
      blockIpv6Dns: json['blockIpv6Dns'] as bool? ?? false,
      disableIpv6WhenConnected:
          json['disableIpv6WhenConnected'] as bool? ?? true,
      transportProtocol:
          transportProtocolFromName(json['transportProtocol'] as String?),
      tunnelMode: tunnelInterfaceModeFromName(json['tunnelMode'] as String?),
      proxyShareEnabled: json['proxyShareEnabled'] as bool? ?? false,
      proxyShareMode: proxyShareModeFromName(json['proxyShareMode'] as String?),
    );
  }

  @override
  List<Object?> get props => [
        killSwitchMode,
        forceDnsThroughTunnel,
        blockLocalDns,
        blockIpv6Dns,
        disableIpv6WhenConnected,
        transportProtocol,
        tunnelMode,
        proxyShareEnabled,
        proxyShareMode,
      ];
}

KillSwitchMode killSwitchModeFromName(String? name) {
  return KillSwitchMode.values.firstWhereOrNull((m) => m.name == name) ??
      KillSwitchMode.off;
}

TunnelInterfaceMode tunnelInterfaceModeFromName(String? name) {
  return TunnelInterfaceMode.values.firstWhereOrNull((m) => m.name == name) ??
      TunnelInterfaceMode.tun;
}

ProxyShareMode proxyShareModeFromName(String? name) {
  return ProxyShareMode.values.firstWhereOrNull((m) => m.name == name) ??
      ProxyShareMode.http;
}
