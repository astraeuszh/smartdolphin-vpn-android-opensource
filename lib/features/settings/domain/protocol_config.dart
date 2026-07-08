import 'package:equatable/equatable.dart';

import 'vpn_protocol.dart';

class ProtocolConfig extends Equatable {
  const ProtocolConfig({
    this.protocol = VpnProtocol.wireGuard,
    this.mtu = 1280,
    this.keepaliveSeconds = 25,
    this.dnsOption = VpnDnsOption.google,
    this.customDnsServers = const ['8.8.8.8'],
  });

  final VpnProtocol protocol;
  final int mtu;
  final int keepaliveSeconds;
  final VpnDnsOption dnsOption;
  final List<String> customDnsServers;

  List<String> get resolvedDnsServers {
    switch (dnsOption) {
      case VpnDnsOption.google:
        return const ['8.8.8.8', '8.8.4.4'];
      case VpnDnsOption.cloudflare:
        return const ['1.1.1.1', '1.0.0.1'];
      case VpnDnsOption.dns114:
        return const ['114.114.114.114', '114.114.115.115'];
      case VpnDnsOption.quad9:
        return const ['9.9.9.9', '149.112.112.112'];
      case VpnDnsOption.custom:
        if (customDnsServers.isEmpty) return const ['8.8.8.8'];
        return customDnsServers;
    }
  }

  ProtocolConfig copyWith({
    VpnProtocol? protocol,
    int? mtu,
    int? keepaliveSeconds,
    VpnDnsOption? dnsOption,
    List<String>? customDnsServers,
  }) {
    return ProtocolConfig(
      protocol: protocol ?? this.protocol,
      mtu: mtu ?? this.mtu,
      keepaliveSeconds: keepaliveSeconds ?? this.keepaliveSeconds,
      dnsOption: dnsOption ?? this.dnsOption,
      customDnsServers: customDnsServers ?? this.customDnsServers,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'protocol': protocol.name,
      'mtu': mtu,
      'keepalive': keepaliveSeconds,
      'dnsOption': dnsOption.name,
      'customDns': customDnsServers,
    };
  }

  factory ProtocolConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const ProtocolConfig();
    }
    return ProtocolConfig(
      protocol: protocolFromName(json['protocol'] as String?),
      mtu: (json['mtu'] as num?)?.toInt() ?? 1280,
      keepaliveSeconds: (json['keepalive'] as num?)?.toInt() ?? 25,
      dnsOption: dnsOptionFromName(json['dnsOption'] as String?),
      customDnsServers: (json['customDns'] as List<dynamic>?)
              ?.map((e) => e as String)
              .where((element) => element.isNotEmpty)
              .toList() ??
          const ['1.1.1.1', '1.0.0.1'],
    );
  }

  @override
  List<Object?> get props => [
        protocol,
        mtu,
        keepaliveSeconds,
        dnsOption,
        customDnsServers,
      ];
}
