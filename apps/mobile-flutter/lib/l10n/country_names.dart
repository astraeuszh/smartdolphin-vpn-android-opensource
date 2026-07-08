import 'package:flutter/widgets.dart';

import '../features/servers/data/all_countries.dart';

/// 与 [allCountries] 中文名并行，供非中文界面显示。
const Map<String, String> kCountryNamesEn = {
  'HK': 'Hong Kong',
  'US': 'United States',
  'TW': 'Taiwan',
  'CN': 'China',
  'JP': 'Japan',
  'KR': 'South Korea',
  'SG': 'Singapore',
  'TH': 'Thailand',
  'VN': 'Vietnam',
  'ID': 'Indonesia',
  'MY': 'Malaysia',
  'PH': 'Philippines',
  'IN': 'India',
  'AE': 'United Arab Emirates',
  'SA': 'Saudi Arabia',
  'IL': 'Israel',
  'TR': 'Turkey',
  'RU': 'Russia',
  'DE': 'Germany',
  'FR': 'France',
  'GB': 'United Kingdom',
  'IT': 'Italy',
  'ES': 'Spain',
  'NL': 'Netherlands',
  'PL': 'Poland',
  'SE': 'Sweden',
  'NO': 'Norway',
  'FI': 'Finland',
  'CA': 'Canada',
  'AU': 'Australia',
  'NZ': 'New Zealand',
  'BR': 'Brazil',
  'MX': 'Mexico',
  'AR': 'Argentina',
  'CL': 'Chile',
  'CO': 'Colombia',
  'ZA': 'South Africa',
  'EG': 'Egypt',
  'NG': 'Nigeria',
  'KE': 'Kenya',
  'MA': 'Morocco',
  'GH': 'Ghana',
  'RO': 'Romania',
  'UA': 'Ukraine',
  'CZ': 'Czechia',
  'HU': 'Hungary',
  'GR': 'Greece',
  'PT': 'Portugal',
  'BE': 'Belgium',
  'AT': 'Austria',
  'CH': 'Switzerland',
  'IE': 'Ireland',
  'DK': 'Denmark',
  'BG': 'Bulgaria',
  'HR': 'Croatia',
  'RS': 'Serbia',
  'SK': 'Slovakia',
  'SI': 'Slovenia',
  'LT': 'Lithuania',
  'LV': 'Latvia',
  'EE': 'Estonia',
  'BY': 'Belarus',
  'KZ': 'Kazakhstan',
  'PK': 'Pakistan',
  'BD': 'Bangladesh',
  'LK': 'Sri Lanka',
  'MM': 'Myanmar',
  'KH': 'Cambodia',
  'LA': 'Laos',
  'NP': 'Nepal',
  'IR': 'Iran',
  'IQ': 'Iraq',
  'JO': 'Jordan',
  'LB': 'Lebanon',
  'KW': 'Kuwait',
  'BH': 'Bahrain',
  'OM': 'Oman',
  'QA': 'Qatar',
  'YE': 'Yemen',
  'AZ': 'Azerbaijan',
  'GE': 'Georgia',
  'AM': 'Armenia',
  'UZ': 'Uzbekistan',
  'TM': 'Turkmenistan',
  'TJ': 'Tajikistan',
  'KG': 'Kyrgyzstan',
  'MN': 'Mongolia',
  'AF': 'Afghanistan',
  'EC': 'Ecuador',
  'PE': 'Peru',
  'VE': 'Venezuela',
  'BO': 'Bolivia',
  'PY': 'Paraguay',
  'UY': 'Uruguay',
  'CR': 'Costa Rica',
  'PA': 'Panama',
  'GT': 'Guatemala',
  'HN': 'Honduras',
  'SV': 'El Salvador',
  'NI': 'Nicaragua',
  'DO': 'Dominican Republic',
  'JM': 'Jamaica',
  'TT': 'Trinidad and Tobago',
  'PR': 'Puerto Rico',
  'CU': 'Cuba',
  'BA': 'Bosnia and Herzegovina',
  'MK': 'North Macedonia',
  'AL': 'Albania',
  'ME': 'Montenegro',
  'MD': 'Moldova',
  'LU': 'Luxembourg',
  'CY': 'Cyprus',
  'MT': 'Malta',
  'IS': 'Iceland',
  'ET': 'Ethiopia',
  'TZ': 'Tanzania',
  'UG': 'Uganda',
  'ZW': 'Zimbabwe',
  'MZ': 'Mozambique',
  'AO': 'Angola',
  'CM': 'Cameroon',
  'CI': 'Côte d\'Ivoire',
  'SN': 'Senegal',
  'TN': 'Tunisia',
  'LY': 'Libya',
  'SD': 'Sudan',
  'DZ': 'Algeria',
  'BW': 'Botswana',
  'NA': 'Namibia',
  'MG': 'Madagascar',
  'RW': 'Rwanda',
  'SO': 'Somalia',
  'ZM': 'Zambia',
  'MW': 'Malawi',
  'BJ': 'Benin',
  'BF': 'Burkina Faso',
  'ML': 'Mali',
  'NE': 'Niger',
  'TD': 'Chad',
  'GA': 'Gabon',
  'CG': 'Republic of the Congo',
  'CD': 'Democratic Republic of the Congo',
  'SY': 'Syria',
  'BN': 'Brunei',
  'MV': 'Maldives',
  'BT': 'Bhutan',
};

final Map<String, String> kCountryNamesJa = {
  ...kCountryNamesEn,
  'HK': '香港',
  'US': 'アメリカ合衆国',
  'SG': 'シンガポール',
  'TW': '台湾',
  'CN': '中国',
  'JP': '日本',
  'KR': '韓国',
  'TH': 'タイ',
  'VN': 'ベトナム',
  'MY': 'マレーシア',
  'PH': 'フィリピン',
  'ID': 'インドネシア',
  'IN': 'インド',
  'AU': 'オーストラリア',
  'GB': 'イギリス',
  'DE': 'ドイツ',
  'FR': 'フランス',
  'RU': 'ロシア',
  'CA': 'カナダ',
  'BR': 'ブラジル',
};

final Map<String, String> kCountryNamesKo = {
  ...kCountryNamesEn,
  'HK': '홍콩',
  'US': '미국',
  'SG': '싱가포르',
  'TW': '대만',
  'CN': '중국',
  'JP': '일본',
  'KR': '한국',
  'TH': '태국',
  'VN': '베트남',
  'MY': '말레이시아',
  'PH': '필리핀',
  'ID': '인도네시아',
  'IN': '인도',
  'AU': '호주',
  'GB': '영국',
  'DE': '독일',
  'FR': '프랑스',
  'RU': '러시아',
  'CA': '캐나다',
  'BR': '브라질',
};

final Map<String, String> kCountryNamesDe = {
  ...kCountryNamesEn,
  'US': 'Vereinigte Staaten',
  'GB': 'Vereinigtes Königreich',
  'HK': 'Hongkong',
};

final Map<String, String> kCountryNamesFr = {
  ...kCountryNamesEn,
  'US': 'États-Unis',
  'GB': 'Royaume-Uni',
  'HK': 'Hong Kong',
};

final Map<String, String> kCountryNamesEs = {
  ...kCountryNamesEn,
  'US': 'Estados Unidos',
  'GB': 'Reino Unido',
};

final Map<String, String> kCountryNamesPt = {
  ...kCountryNamesEn,
  'US': 'Estados Unidos',
  'GB': 'Reino Unido',
};

final Map<String, String> _zhNames = {
  for (final e in allCountries) e.$1: e.$2,
};

/// 简/繁界面用中文名；其它语言用对应本地化名称（无翻译时回退英文）。
String countryDisplayName(Locale locale, String code) {
  final c = code.toUpperCase();
  if (locale.languageCode == 'zh') {
    return _zhNames[c] ?? kCountryNamesEn[c] ?? c;
  }
  final localized = switch (locale.languageCode) {
    'ja' => kCountryNamesJa[c],
    'ko' => kCountryNamesKo[c],
    'de' => kCountryNamesDe[c],
    'fr' => kCountryNamesFr[c],
    'es' => kCountryNamesEs[c],
    'pt' => kCountryNamesPt[c],
    _ => null,
  };
  return localized ?? kCountryNamesEn[c] ?? c;
}

/// 搜索节点：匹配国家码、英文名、中文名（用户用任意语言输入都能搜）。
bool countryMatchesSearch(String queryLower, String countryCode) {
  final q = queryLower.trim();
  if (q.isEmpty) return true;
  final code = countryCode.toUpperCase();
  if (code.toLowerCase().startsWith(q)) return true;
  final en = (kCountryNamesEn[code] ?? '').toLowerCase();
  final zh = (_zhNames[code] ?? '').toLowerCase();
  final ja = (kCountryNamesJa[code] ?? '').toLowerCase();
  final ko = (kCountryNamesKo[code] ?? '').toLowerCase();
  return en.contains(q) || zh.contains(q) || ja.contains(q) || ko.contains(q);
}
