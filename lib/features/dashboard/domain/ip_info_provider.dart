import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../l10n/app_localizations.dart';
import '../../../l10n/country_names.dart';
import '../../servers/domain/server_display_name.dart';

class IpInfo {
  const IpInfo({
    this.ip,
    this.country,
    this.countryCode,
    this.region,
    this.city,
    this.isp,
    this.org,
    this.timezone,
    this.loc,
    this.asn,
    this.error,
  });

  final String? ip;
  final String? country;
  final String? countryCode;
  final String? region;
  final String? city;
  final String? isp;
  final String? org;
  final String? timezone;
  final String? loc;
  final String? asn;
  final String? error;

  bool get hasData => ip != null && ip!.isNotEmpty;

  /// 优先 org/isp（运营商归属），避免 geo city 与线路省份不一致。
  String displayLocationFor(AppLocalizations l10n) => formatIpDisplayLocation(
        countryCode: countryCode,
        region: region,
        city: city,
        org: org,
        isp: isp,
        country: country,
        languageTag: languageTagForL10n(l10n),
      );

  /// 首页/仪表盘地址：固定英文。
  String get displayLocationEnglish => formatIpDisplayLocation(
        countryCode: countryCode,
        region: region,
        city: city,
        org: org,
        isp: isp,
        country: country,
        languageTag: 'en',
      );

  String get countryNameEnglish {
    final code = countryCode?.toUpperCase();
    if (code != null && code.isNotEmpty) {
      return kCountryNamesEn[code] ?? country ?? code;
    }
    return country ?? '--';
  }

  String localizedCountryFor(AppLocalizations l10n) =>
      localizedCountryName(countryCode, l10n);

  String get coordinates => loc ?? '--';
}

Future<IpInfo> fetchIpInfo() async {
  try {
    final resp = await http
        .get(Uri.parse('https://ipinfo.io/json'))
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) {
      return const IpInfo(error: '__fetch_failed__');
    }
    final decoded = jsonDecode(resp.body);
    if (decoded is! Map<String, dynamic>) return const IpInfo(error: '__parse_failed__');
    final j = decoded;
    final orgRaw = j['org'] as String?;
    return IpInfo(
      ip: j['ip'] as String?,
      country: j['country'] == null ? null : _countryName(j['country'] as String?),
      countryCode: j['country'] as String?,
      region: j['region'] as String?,
      city: j['city'] as String?,
      isp: _parseOrg(orgRaw),
      org: _parseOrg(orgRaw),
      timezone: j['timezone'] as String?,
      loc: j['loc'] as String?,
      asn: _parseAsn(orgRaw),
    );
  } catch (e) {
    return IpInfo(error: e.toString());
  }
}

final ipInfoProvider = FutureProvider<IpInfo>((ref) => fetchIpInfo());

bool isCnLikeCountryCode(String? code) {
  final cc = (code ?? '').toUpperCase();
  return cc == 'CN' || cc == 'HK' || cc == 'TW' || cc == 'MO';
}

String? cnShortRegion(String? raw) {
  if (raw == null) return null;
  var name = raw.trim();
  if (name.isEmpty) return null;
  const stripSuffixes = [
    '维吾尔自治区',
    '回族自治区',
    '壮族自治区',
    '自治区',
    '特别行政区',
    'Province',
    'province',
    ' Province',
  ];
  for (final s in stripSuffixes) {
    if (name.endsWith(s)) {
      name = name.substring(0, name.length - s.length).trim();
      break;
    }
  }
  if (name.endsWith('省') || name.endsWith('市')) {
    name = name.substring(0, name.length - 1);
  }
  return name.isEmpty ? null : name;
}

String? provinceFromOrg(String? orgOrIsp) {
  if (orgOrIsp == null || orgOrIsp.isEmpty) return null;
  const cnProvinces = [
    '北京', '天津', '上海', '重庆',
    '河北', '山西', '辽宁', '吉林', '黑龙江',
    '江苏', '浙江', '安徽', '福建', '江西', '山东',
    '河南', '湖北', '湖南', '广东', '海南',
    '四川', '贵州', '云南', '陕西', '甘肃', '青海',
    '内蒙古', '广西', '西藏', '宁夏', '新疆',
    '香港', '澳门', '台湾',
  ];
  for (final p in cnProvinces) {
    if (orgOrIsp.contains(p)) return p;
  }
  const enProvinces = {
    'beijing': '北京',
    'tianjin': '天津',
    'shanghai': '上海',
    'chongqing': '重庆',
    'hebei': '河北',
    'shanxi': '山西',
    'liaoning': '辽宁',
    'jilin': '吉林',
    'heilongjiang': '黑龙江',
    'jiangsu': '江苏',
    'zhejiang': '浙江',
    'anhui': '安徽',
    'fujian': '福建',
    'jiangxi': '江西',
    'shandong': '山东',
    'henan': '河南',
    'hubei': '湖北',
    'hunan': '湖南',
    'guangdong': '广东',
    'hainan': '海南',
    'sichuan': '四川',
    'guizhou': '贵州',
    'yunnan': '云南',
    'shaanxi': '陕西',
    'gansu': '甘肃',
    'qinghai': '青海',
    'inner mongolia': '内蒙古',
    'guangxi': '广西',
    'tibet': '西藏',
    'ningxia': '宁夏',
    'xinjiang': '新疆',
    'hong kong': '香港',
    'macau': '澳门',
    'taiwan': '台湾',
  };
  final lower = orgOrIsp.toLowerCase();
  for (final entry in enProvinces.entries) {
    if (lower.contains(entry.key)) return entry.value;
  }
  return cnShortRegion(orgOrIsp);
}

String formatIpDisplayLocation({
  String? countryCode,
  String? region,
  String? city,
  String? org,
  String? isp,
  String? country,
  String? languageTag,
}) {
  final useChineseGeo = languageTag == 'zh' || languageTag == 'zh_Hant';
  if (useChineseGeo && isCnLikeCountryCode(countryCode)) {
    return provinceFromOrg(org ?? isp) ??
        cnShortRegion(region) ??
        cnShortRegion(city) ??
        region ??
        city ??
        country ??
        '--';
  }

  if (city != null && city.isNotEmpty) return city;
  if (region != null && region.isNotEmpty) return region;
  if (country != null && country.isNotEmpty) return country;
  return '--';
}

String? _countryName(String? code) {
  if (code == null) return null;
  const names = {
    'US': 'United States',
    'CN': 'China',
    'HK': 'Hong Kong',
    'JP': 'Japan',
    'GB': 'United Kingdom',
    'DE': 'Germany',
    'FR': 'France',
    'SG': 'Singapore',
    'TW': 'Taiwan',
    'KR': 'South Korea',
  };
  return names[code.toUpperCase()] ?? code;
}

String? _parseOrg(String? org) {
  if (org == null) return null;
  final idx = org.indexOf(' ');
  return idx > 0 ? org.substring(idx + 1).trim() : org;
}

String? _parseAsn(String? org) {
  if (org == null) return null;
  if (org.toUpperCase().startsWith('AS')) {
    final idx = org.indexOf(' ');
    return idx > 0 ? org.substring(0, idx) : org;
  }
  return null;
}
