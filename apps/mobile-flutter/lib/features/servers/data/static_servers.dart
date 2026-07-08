import '../domain/server.dart';

/// SmartDolphin self-owned nodes. Dolphin-Core builds runtime configs from
/// node_table.dart; the OpenVPN base64 values are deprecated placeholders.
const List<Server> smartDolphinStaticServers = [
  Server(
    id: 'smartdolphin-nl',
    name: 'Netherlands - SmartDolphin',
    countryCode: 'NL',
    countryName: 'Netherlands',
    publicKey: 'reality',
    endpoint: '206.245.157.199:8444',
    allowedIps: '0.0.0.0/0, ::/0',
    hostName: 'astraeuszhao.com',
    ip: '206.245.157.199',
    openVpnConfigDataBase64: _deprecatedConfigBase64,
    regionName: 'Netherlands',
    cityName: 'Netherlands',
  ),
  Server(
    id: 'smartdolphin-us',
    name: 'United States - SmartDolphin',
    countryCode: 'US',
    countryName: 'United States',
    publicKey: 'reality',
    endpoint: '166.88.197.246:8444',
    allowedIps: '0.0.0.0/0, ::/0',
    hostName: 'smartdolphin.top',
    ip: '166.88.197.246',
    openVpnConfigDataBase64: _deprecatedConfigBase64,
    regionName: 'United States',
    cityName: 'Seattle',
  ),
  Server(
    id: 'smartdolphin-sg',
    name: 'Singapore - SmartDolphin',
    countryCode: 'SG',
    countryName: 'Singapore',
    publicKey: 'reality',
    endpoint: '[2605:e440:16::334]:8444',
    allowedIps: '0.0.0.0/0, ::/0',
    hostName: 'smartdolphinvpn.com',
    ip: '2605:e440:16::334',
    openVpnConfigDataBase64: _deprecatedConfigBase64,
    regionName: 'Singapore',
    cityName: 'Singapore',
  ),
];

const _deprecatedConfigBase64 = 'ZGVwcmVjYXRlZA==';
