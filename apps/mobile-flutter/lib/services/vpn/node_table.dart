import 'dart:convert';

/// Canonical node table and sing-box config generation for Dolphin-Core.
const String kVlessUuid = 'e6171791-01a9-47b9-8371-e5c8a1b84ffb';
// sing-box expects the URL-safe Base64 form of the X25519 public key.
const String kRealityPbk = '-vjbn6uLtRHtqFwM9GOX2tLJasW8F9fS5MsQdf9cfGo';
const String kRealityShort = 'd4cd34b97f9631a6';
const String kRealitySni = 'dl.google.com';
const String kHy2Password = 'REDACTED_HYSTERIA_PASSWORD';
const String kWgPrivateKey = 'REDACTED_WIREGUARD_PRIVATE_KEY';
// WireGuard outbound peer_public_key is the server interface public key.
// The corresponding client public key (derived from kWgPrivateKey) is
// registered on the server as an allowed peer.
const String kWgPeerPubKey = 'REDACTED_WIREGUARD_PEER_PUBLIC_KEY';
const String kWgLocalAddr = '10.7.0.2/32';

const List<String> kNodeIpCidrs = [
  '206.245.157.199/32',
  '23.27.134.86/32',
  '194.87.10.236/32',
  '2605:e440:16::334/128',
];

enum SdProtocol { reality, hysteria2, wireguard }

class SdTunnelCredential {
  const SdTunnelCredential({
    required this.vlessUuid,
    required this.hysteriaPassword,
    required this.expiresAt,
    required this.readyAt,
  });

  final String vlessUuid;
  final String hysteriaPassword;
  final int expiresAt;
  final int readyAt;
}

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
    required this.endpointHost,
    required this.h2Sni,
    required this.realityPort,
    required this.flag,
  });

  final String tag;
  final String host;

  /// Stable IPv4 transport endpoint. Reality must not wait on an unusable AAAA
  /// route on mobile networks; IPv6 remains available for tunneled traffic.
  final String endpointHost;
  final String h2Sni;
  final int realityPort;
  final String flag;
}

const List<SdNode> kNodes = [
  SdNode(
    tag: 'Netherlands',
    host: '206.245.157.199',
    endpointHost: '206.245.157.199',
    h2Sni: 'astraeuszhao.com',
    realityPort: 8444,
    flag: 'NL',
  ),
  SdNode(
    tag: 'United States',
    host: '23.27.134.86',
    endpointHost: '23.27.134.86',
    h2Sni: 'smartdolphinvpn.com',
    realityPort: 8444,
    flag: 'US',
  ),
  SdNode(
    tag: 'Singapore',
    host: '194.87.10.236',
    endpointHost: '194.87.10.236',
    // smartdolphin.top still resolves to an old VPS, so Let's Encrypt cannot
    // issue/renew that certificate on the Singapore node yet. The server is
    // currently configured with the shared smartdolphinvpn.com certificate.
    h2Sni: 'smartdolphinvpn.com',
    realityPort: 8444,
    flag: 'SG',
  ),
];

SdNode nodeForHostOrCountry(String? host, String? country) {
  if (host != null && host.isNotEmpty) {
    for (final n in kNodes) {
      if (n.host == host) return n;
    }
  }
  if (country != null && country.isNotEmpty) {
    final c = country.toLowerCase();
    if (c.contains('us') || c.contains('united') || c.contains('america')) {
      return kNodes.firstWhere((n) => n.flag == 'US',
          orElse: () => kNodes.first);
    }
    if (c.contains('nl') ||
        c.contains('netherlands') ||
        c.contains('holland')) {
      return kNodes.firstWhere((n) => n.flag == 'NL',
          orElse: () => kNodes.first);
    }
    if (c.contains('sg') || c.contains('singapore')) {
      return kNodes.firstWhere((n) => n.flag == 'SG',
          orElse: () => kNodes.first);
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
  '.amap.com',
  '.ctdns.cn',
  '.dnspod.cn',
];

const _localDnsResolverIps = ['223.5.5.5/32', '223.6.6.6/32'];

Map<String, dynamic> _remoteDnsServer(bool forceDnsThroughTunnel) {
  if (forceDnsThroughTunnel) {
    return {
      'tag': 'remote-dns',
      'address': 'https://dns.google/dns-query',
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

Map<String, dynamic> _proxyOutbound(
  SdNode n,
  SdProtocol proto,
  SdTunnelCredential? credential,
) {
  switch (proto) {
    case SdProtocol.hysteria2:
      return {
        'type': 'hysteria2',
        'tag': 'proxy',
        'server': n.endpointHost,
        'server_port': 443,
        // Managed nodes use one stable credential. Imported profiles carry
        // their own password and never pass through this builder.
        'password': kHy2Password,
        'tls': {
          'enabled': true,
          'server_name': n.h2Sni,
          'alpn': ['h3'],
        },
      };
    case SdProtocol.wireguard:
      // sing-box 1.13 removed the legacy WireGuard outbound. The endpoint is
      // attached directly to the `proxy` route tag in buildSingBoxConfig.
      throw StateError('WireGuard is configured as an endpoint');
    case SdProtocol.reality:
      return {
        'type': 'vless',
        'tag': 'proxy',
        'server': n.endpointHost,
        'server_port': n.realityPort,
        // Managed Reality nodes use this stable bootstrap credential. Account
        // APIs are deliberately not part of the tunnel establishment path.
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

Map<String, dynamic> _wireGuardEndpoint(SdNode node) {
  return {
    'type': 'wireguard',
    // Keep the endpoint tag aligned with every other managed protocol so
    // routing, the Clash API delay probe, and status collection share it.
    'tag': 'proxy',
    'name': 'dolphin-wg',
    'mtu': 1408,
    'address': [kWgLocalAddr],
    'private_key': kWgPrivateKey,
    'peers': [
      {
        'address': node.endpointHost,
        'port': 51820,
        'public_key': kWgPeerPubKey,
        'allowed_ips': ['0.0.0.0/0'],
        // Keeps mobile NAT state valid without any polling work in Flutter.
        'persistent_keepalive_interval': 25,
      },
    ],
  };
}

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
  SdTunnelCredential? tunnelCredential,
  String logLevel = 'info',
}) {
  final route = <String, dynamic>{
    'auto_detect_interface': true,
    'override_android_vpn': true,
    'final': 'proxy',
    'rules': <Map<String, dynamic>>[
      {'protocol': 'dns', 'outbound': 'dns-out'},
      {'ip_cidr': kNodeIpCidrs, 'outbound': 'direct'},
      {'ip_cidr': _localDnsResolverIps, 'outbound': 'direct'},
      {
        'domain': [
          'astraeuszhao.com',
          'smartdolphin.top',
          'smartdolphinvpn.com',
          'astraeus.smartdolphin.top',
        ],
        'outbound': 'direct',
      },
      {
        'ip_cidr': ['127.0.0.0/8'],
        'outbound': 'direct'
      },
      if (bypassLan)
        {
          'ip_cidr': [
            '10.0.0.0/8',
            '172.16.0.0/12',
            '192.168.0.0/16',
            '169.254.0.0/16'
          ],
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
        'inet4_route_exclude_address': kNodeIpCidrs,
        'stack': 'system',
        'sniff': true,
        'sniff_override_destination': true,
        'endpoint_independent_nat': true,
        if (includePackages.isNotEmpty) 'include_package': includePackages,
        if (includePackages.isEmpty && excludePackages.isNotEmpty)
          'exclude_package': excludePackages,
      },
    ],
    'outbounds': [
      if (protocol != SdProtocol.wireguard)
        _proxyOutbound(node, protocol, tunnelCredential),
      {'type': 'direct', 'tag': 'direct'},
      {'type': 'block', 'tag': 'block'},
      {'type': 'dns', 'tag': 'dns-out'},
    ],
    if (protocol == SdProtocol.wireguard)
      'endpoints': [_wireGuardEndpoint(node)],
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
