import '../domain/server.dart';

/// SmartDolphin 自有服务器：香港 1、香港 2、美国（Dolphin-Core / sing-box）。
/// `ip` 映射到 node_table.dart 的 kNodes；OpenVPN base64 仅历史占位，新内核不用。
const List<Server> smartDolphinStaticServers = [
  Server(
    id: 'smartdolphin-hk',
    name: 'Hong Kong 1 • SmartDolphin',
    countryCode: 'HK',
    countryName: 'Hong Kong',
    publicKey: 'reality',
    endpoint: '38.76.194.13:443',
    allowedIps: '0.0.0.0/0, ::/0',
    hostName: '38.76.194.13',
    ip: '38.76.194.13',
    openVpnConfigDataBase64: _hkOpenVpnConfigBase64,
    regionName: 'Hong Kong',
    cityName: 'Hong Kong 1',
  ),
  Server(
    id: 'smartdolphin-hk2',
    name: 'Hong Kong 2 • SmartDolphin',
    countryCode: 'HK',
    countryName: 'Hong Kong',
    publicKey: 'reality',
    endpoint: '154.219.104.222:8444',
    allowedIps: '0.0.0.0/0, ::/0',
    hostName: '154.219.104.222',
    ip: '154.219.104.222',
    openVpnConfigDataBase64: _hkOpenVpnConfigBase64,
    regionName: 'Hong Kong',
    cityName: 'Hong Kong 2',
  ),
  Server(
    id: 'smartdolphin-us',
    name: 'United States • SmartDolphin',
    countryCode: 'US',
    countryName: 'United States',
    publicKey: 'reality',
    endpoint: '154.9.26.253:443',
    allowedIps: '0.0.0.0/0, ::/0',
    hostName: 'smartdolphin.top',
    ip: '154.9.26.253',
    openVpnConfigDataBase64: _usOpenVpnConfigBase64,
    regionName: 'United States',
    cityName: 'Los Angeles',
  ),
];

// Legacy OpenVPN config placeholders. Dolphin-Core (sing-box) builds its own
// config from node_table.dart and never reads these — they only satisfy the
// non-empty config gate in session_controller. Base64 of "deprecated".
const _hkOpenVpnConfigBase64 = 'ZGVwcmVjYXRlZA==';
const _usOpenVpnConfigBase64 = 'ZGVwcmVjYXRlZA==';
