import '../../../l10n/app_localizations.dart';
import '../../../l10n/country_names.dart';
import '../data/country_card.dart';
import 'server.dart';

/// SmartDolphin 节点标题随界面语言变化。
String localizedServerDisplayName(Server s, AppLocalizations l10n) {
  switch (s.id) {
    case 'smartdolphin-hk':
      return l10n.serverPinnedHk;
    case 'smartdolphin-us':
      return l10n.serverPinnedUs;
    case 'smartdolphin-sg':
      return l10n.serverPinnedSg;
    default:
      return s.name;
  }
}

/// 节点所在城市/地区（节点列表等 UI，随界面语言变化）。
String localizedServerLocation(Server s, AppLocalizations l10n) {
  switch (s.id) {
    case 'smartdolphin-hk':
      return l10n.geoCityHongKong;
    case 'smartdolphin-us':
      return l10n.geoCityLosAngeles;
    case 'smartdolphin-sg':
      return l10n.geoCitySingapore;
    default:
      return s.cityName ?? s.regionName ?? localizedCountryName(s.countryCode, l10n);
  }
}

String localizedCountryName(String? countryCode, AppLocalizations l10n) {
  if (countryCode == null || countryCode.isEmpty) return '--';
  return countryDisplayName(l10n.locale, countryCode);
}

extension CountryCardDisplay on CountryCard {
  String localizedName(AppLocalizations l10n) =>
      countryDisplayName(l10n.locale, countryCode);

  bool get isLatencyTimeout =>
      latencyMs != null && (latencyMs! > 800 || latencyMs! == 9999);

  String latencyLabel(AppLocalizations l10n) {
    if (latencyMs == null) return '--';
    if (isLatencyTimeout) return l10n.serverLatencyTimeout;
    return '${latencyMs}ms';
  }
}

String languageTagForL10n(AppLocalizations l10n) {
  final locale = l10n.locale;
  if (locale.languageCode == 'zh') {
    if (locale.scriptCode == 'Hant' ||
        locale.countryCode == 'TW' ||
        locale.countryCode == 'HK') {
      return 'zh_Hant';
    }
    return 'zh';
  }
  if (locale.countryCode != null && locale.countryCode!.isNotEmpty) {
    return '${locale.languageCode}_${locale.countryCode}';
  }
  return locale.languageCode;
}

/// 首页/仪表盘「地址」固定英文，不随界面语言变化。
String englishServerAddress(Server s) {
  switch (s.id) {
    case 'smartdolphin-hk':
      return 'Hong Kong';
    case 'smartdolphin-us':
      return 'Los Angeles';
    case 'smartdolphin-sg':
      return 'Singapore';
    default:
      if (s.cityName != null && s.cityName!.isNotEmpty) return s.cityName!;
      if (s.regionName != null && s.regionName!.isNotEmpty) return s.regionName!;
      return kCountryNamesEn[s.countryCode.toUpperCase()] ?? s.countryCode;
  }
}
