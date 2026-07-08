import '../domain/server.dart';

/// SmartDolphin self-owned nodes. Dolphin-Core builds runtime configs from
/// node_table.dart; the OpenVPN base64 values are deprecated placeholders.
const List<Server> smartDolphinStaticServers = [
  Server(
    id: 'smartdolphin-nl',
    name: 'Netherlands Amsterdam - SmartDolphin',
    countryCode: 'NL',
    countryName: 'Netherlands',
    publicKey: 'reality',
    endpoint: '206.245.157.199:8444',
    allowedIps: '0.0.0.0/0, ::/0',
    hostName: 'astraeuszhao.com',
    ip: '206.245.157.199',
    openVpnConfigDataBase64: _deprecatedConfigBase64,
    regionName: 'North Holland',
    cityName: 'Amsterdam',
  ),
  Server(
    id: 'smartdolphin-us',
    name: 'United States San Jose - SmartDolphin',
    countryCode: 'US',
    countryName: 'United States',
    publicKey: 'reality',
    endpoint: '23.27.134.86:8444',
    allowedIps: '0.0.0.0/0, ::/0',
    hostName: 'smartdolphinvpn.com',
    ip: '23.27.134.86',
    openVpnConfigDataBase64: _deprecatedConfigBase64,
    regionName: 'California',
    cityName: 'San Jose',
  ),
  Server(
    id: 'smartdolphin-sg',
    name: 'Singapore - SmartDolphin',
    countryCode: 'SG',
    countryName: 'Singapore',
    publicKey: 'reality',
    endpoint: '194.87.10.236:8444',
    allowedIps: '0.0.0.0/0, ::/0',
    hostName: 'smartdolphin.top',
    ip: '194.87.10.236',
    openVpnConfigDataBase64: _deprecatedConfigBase64,
    regionName: 'Singapore',
    cityName: 'Singapore',
  ),
];

const _deprecatedConfigBase64 = 'ZGVwcmVjYXRlZA==';
