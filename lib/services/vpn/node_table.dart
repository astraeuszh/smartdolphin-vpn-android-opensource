import 'dart:convert';

/// Canonical node table + sing-box config generation for the Dolphin-Core
/// (sing-box) engine. Mirrors the Windows client's node_table.go so the same
/// nodes / credentials are used across platforms.

const String kVlessUuid = 'e6171791-01a9-47b9-8371-e5c8a1b84ffb';
const String kRealityPbk = '-vjbn6uLtRHtqFwM9GOX2tLJasW8F9fS5MsQdf9cfGo';
const String kRealityShort = 'd4cd34b97f9631a6';
const String kRealitySni = 'dl.google.com';
const String kHy2Password = 'REDACTED_HYSTERIA_PASSWORD';
const String kWgPrivateKey = 'REDACTED_WIREGUARD_PRIVATE_KEY';
const String kWgPeerPubKey = 'REDACTED_WIREGUARD_PEER_PUBLIC_KEY';
const String kWgLocalAddr = '10.7.0.2/32';

/// Supported transport protocols (must match Windows ProtoReality/…).
enum SdProtocol { reality, hysteria2, wireguard }

SdProtocol sdProtocolFromName(String? name) {
  switch ((name ?? '').toLowerCase().trim()) {
    case 'hysteria2':
    case 'hy2':
    case 'hysteria':
      return SdProtocol.hysteria2;
    case 'wireguard':
    case 'wg':
      return SdProtocol.wireguard;
    default:
      return SdProtocol.reality;
  }
}

class SdNode {
  const SdNode({
    required this.tag,
    required this.host,
    required this.h2Sni,
    required this.realityPort,
    required this.flag,
  });

  final String tag; // outbound tag + UI identity
  final String host; // server IP
  final String h2Sni; // Hysteria2 TLS SNI
  final int realityPort; // VLESS+Reality TCP port
  final String flag; // country flag code (HK / US)
}

/// Authoritative node list (order = display order). Mirrors canonicalNodes().
const List<SdNode> kNodes = [
  SdNode(tag: '香港1', host: '38.76.194.13', h2Sni: 'astraeuszhao.com', realityPort: 443, flag: 'HK'),
  SdNode(tag: '香港2', host: '154.219.104.222', h2Sni: 'smartdolphinvpn.com', realityPort: 8444, flag: 'HK'),
  SdNode(tag: '美国', host: '154.9.26.253', h2Sni: 'smartdolphin.top', realityPort: 443, flag: 'US'),
];

SdNode nodeForHostOrCountry(String? host, String? country) {
  if (host != null && host.isNotEmpty) {
    for (final n in kNodes) {
      if (n.host == host) return n;
    }
  }
  if (country != null && country.isNotEmpty) {
    final c = country.toLowerCase();
    if (c.contains('us') || c.contains('united') || c.contains('美')) {
      return kNodes.firstWhere((n) => n.flag == 'US', orElse: () => kNodes.first);
    }
    if (c.contains('hk') || c.contains('hong') || c.contains('香港')) {
      return kNodes.firstWhere((n) => n.flag == 'HK', orElse: () => kNodes.first);
    }
  }
  return kNodes.first;
}

const _cnDomainSuffixes = [
  '.cn',
  '.中国',
  '.baidu.com',
  '.qq.com',
  '.taobao.com',
  '.tmall.com',
  '.jd.com',
  '.163.com',
  '.bilibili.com',
  '.zhihu.com',
  '.douyin.com',
  '.weixin.qq.com',
  '.alipay.com',
  '.heytapmobi.com',
  '.heytap.com',
  '.heytapimage.com',
  '.coloros.com',
  '.oppo.com',
  '.allawntech.com',
  '.doubao.com',
  '.douyin.com',
  '.amap.com',
  '.ctdns.cn',
  '.dnspod.cn',
];

const _localDnsResolverIps = ['223.5.5.5/32', '223.6.6.6/32'];

/// Upstream DNS through the tunnel — matches Windows (DoH + local resolver bootstrap).
Map<String, dynamic> _remoteDnsServer(bool forceDnsThroughTunnel) {
  if (forceDnsThroughTunnel) {
    return {
      'tag': 'remote-dns',
      'address': 'https://8.8.8.8/dns-query',
      'address_resolver': 'local-dns',
      'detour': 'proxy',
    };
  }
  return {
    'tag': 'remote-dns',
    'address': '8.8.8.8',
    'detour': 'direct',
  };
}

List<Map<String, dynamic>> _dnsRules({
  required bool globalMode,
  required bool forceDnsThroughTunnel,
  required bool blockLocalDns,
}) {
  final rules = <Map<String, dynamic>>[
    // Only direct-routed flows use AliDNS — NOT every outbound (that polluted
    // foreign domains to China CDN IPs → SSL errors + 1000ms+ latency).
    {'outbound': 'direct', 'server': 'local-dns'},
  ];
  if (!globalMode) {
    rules.add({'domain_suffix': _cnDomainSuffixes, 'server': 'local-dns'});
  }
  if (!forceDnsThroughTunnel && !blockLocalDns) {
    rules.add({'outbound': 'any', 'server': 'local-dns'});
  }
  return rules;
}

/// Builds the node's sing-box outbound (tag = "proxy").
Map<String, dynamic> _proxyOutbound(SdNode n, SdProtocol proto) {
  switch (proto) {
    case SdProtocol.hysteria2:
      return {
        'type': 'hysteria2',
        'tag': 'proxy',
        'server': n.host,
        'server_port': 443,
        'password': kHy2Password,
        'tls': {
          'enabled': true,
          'server_name': n.h2Sni,
          'alpn': ['h3'],
        },
      };
    case SdProtocol.wireguard:
      return {
        'type': 'wireguard',
        'tag': 'proxy',
        'server': n.host,
        'server_port': 51820,
        'local_address': [kWgLocalAddr],
        'private_key': kWgPrivateKey,
        'peer_public_key': kWgPeerPubKey,
        'mtu': 1408,
      };
    case SdProtocol.reality:
      return {
        'type': 'vless',
        'tag': 'proxy',
        'server': n.host,
        'server_port': n.realityPort,
        'uuid': kVlessUuid,
        'flow': 'xtls-rprx-vision',
        'multiplex': {'enabled': false},
        'tcp_keep_alive': '15s',
        'tcp_keep_alive_interval': '5s',
        'tls': {
          'enabled': true,
          'server_name': kRealitySni,
          'utls': {'enabled': true, 'fingerprint': 'chrome'},
          'reality': {
            'enabled': true,
            'public_key': kRealityPbk,
            'short_id': kRealityShort,
          },
        },
      };
  }
}

/// Generates a full sing-box config JSON string for the Android (libbox) engine.
///
/// - [globalMode] true → route everything through the proxy; false → keep
///   mainland-China traffic on the direct outbound (smart split).
/// - [dnsServer] upstream DNS used through the tunnel (default 8.8.8.8).
String buildSingBoxConfig({
  required SdNode node,
  required SdProtocol protocol,
  bool globalMode = false,
  String dnsServer = '8.8.8.8',
  int mtu = 1420,
  bool disableIpv6 = true,
  bool bypassLan = true,
  bool autoRouteSystem = true,
  bool forceDnsThroughTunnel = true,
  bool blockLocalDns = true,
  List<String> includePackages = const [],
  List<String> excludePackages = const [],
  String logLevel = 'info',
}) {
  final route = <String, dynamic>{
    'auto_detect_interface': true,
    'override_android_vpn': true,
    'final': 'proxy',
    'rules': <Map<String, dynamic>>[
      {'protocol': 'dns', 'outbound': 'dns-out'},
      // Node IPs must dial direct so the handshake never loops through the tunnel.
      {
        'ip_cidr': ['38.76.194.13/32', '154.219.104.222/32', '154.9.26.253/32'],
        'outbound': 'direct',
      },
      // Local resolver must never loop through the proxy.
      {'ip_cidr': _localDnsResolverIps, 'outbound': 'direct'},
      {
        'domain': ['astraeuszhao.com', 'astraeuszhao.top', 'smartdolphin.top', 'smartdolphinvpn.com'],
        'outbound': 'direct',
      },
      // Loopback always bypasses the tunnel.
      {
        'ip_cidr': ['127.0.0.0/8'],
        'outbound': 'direct',
      },
      // Private / link-local ranges bypass the tunnel only when "bypass LAN" is
      // on (lets the user reach routers, printers, NAS, casting, etc. directly).
      if (bypassLan)
        {
          'ip_cidr': ['10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16', '169.254.0.0/16'],
          'outbound': 'direct',
        },
      if (!globalMode)
        {
          'domain_suffix': _cnDomainSuffixes,
          'outbound': 'direct',
        },
    ],
  };

  final config = <String, dynamic>{
    'log': {'level': logLevel, 'timestamp': true},
    // Foreign domains resolve via 8.8.8.8 through the exit node so CDN edges
    // are near the VPN server — not China-optimised IPs from AliDNS (SSL errors).
    'dns': {
      'servers': [
        _remoteDnsServer(forceDnsThroughTunnel),
        {'tag': 'local-dns', 'address': '223.5.5.5', 'detour': 'direct'},
      ],
      'rules': _dnsRules(
        globalMode: globalMode,
        forceDnsThroughTunnel: forceDnsThroughTunnel,
        blockLocalDns: blockLocalDns,
      ),
      'final': 'remote-dns',
      if (disableIpv6) 'strategy': 'ipv4_only',
    },
    'inbounds': [
      {
        'type': 'tun',
        'tag': 'tun-in',
        'interface_name': 'dolphin-tun',
        'inet4_address': '172.19.0.1/30',
        if (!disableIpv6) 'inet6_address': 'fdfe:dcba:9876::1/126',
        'mtu': mtu,
        'auto_route': autoRouteSystem,
        'strict_route': false,
        'inet4_route_exclude_address': const [
          '38.76.194.13/32',
          '154.219.104.222/32',
          '154.9.26.253/32',
        ],
        'stack': 'system',
        'sniff': true,
        'sniff_override_destination': true,
        'endpoint_independent_nat': true,
        // Per-app split tunnelling. include wins over exclude (sing-box rejects
        // both at once); empty → all apps go through the tunnel.
        if (includePackages.isNotEmpty) 'include_package': includePackages,
        if (includePackages.isEmpty && excludePackages.isNotEmpty) 'exclude_package': excludePackages,
      },
    ],
    'outbounds': [
      _proxyOutbound(node, protocol),
      {'type': 'direct', 'tag': 'direct'},
      {'type': 'block', 'tag': 'block'},
      {'type': 'dns', 'tag': 'dns-out'},
    ],
    'route': route,
    'experimental': {
      'clash_api': {
        'external_controller': '127.0.0.1:9090',
        'access_control_allow_origin': ['*'],
      },
    },
  };

  return jsonEncode(config);
}
