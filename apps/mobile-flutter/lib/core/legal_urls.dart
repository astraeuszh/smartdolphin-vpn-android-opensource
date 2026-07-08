/// Central legal document URLs hosted at doc.smartdolphin.top
class LegalUrls {
  LegalUrls._();

  static const base = 'https://doc.smartdolphin.top';

  /// Map app locale tag → doc site language path segment.
  static String docLangFor(String? localeTag) {
    switch (localeTag) {
      case 'zh':
      case 'zh-CN':
        return 'zh-CN';
      case 'zh_Hant_TW':
      case 'zh-TW':
        return 'zh-TW';
      case 'ja':
        return 'ja';
      case 'ru':
        return 'ru';
      default:
        return 'en';
    }
  }

  static String userAgreementFor(String? localeTag) =>
      '$base/${docLangFor(localeTag)}/software/vpn-android/legal/user-agreement';

  static String disclaimerFor(String? localeTag) =>
      '$base/${docLangFor(localeTag)}/software/vpn-android/disclaimer';

  static String legalNoticeFor(String? localeTag) =>
      '$base/${docLangFor(localeTag)}/software/vpn-android/legal/legal-notice';

  static String openSourceLicenseFor(String? localeTag) =>
      '$base/${docLangFor(localeTag)}/software/vpn-android/legal/open-source';

  static const sdrlTutorialZh = '$base/zh-CN/sdrl/tutorial#use';
  static const sdrlTutorialEn = '$base/en/sdrl/tutorial#use';

  static String sdrlTutorialFor(String? localeTag) =>
      docLangFor(localeTag) == 'zh-CN' ? sdrlTutorialZh : sdrlTutorialEn;

  /// Legacy static URLs (English paths) — prefer *For(locale) in UI.
  static const userAgreement = '$base/en/software/vpn-android/legal/user-agreement';
  static const disclaimer = '$base/en/software/vpn-android/disclaimer';
  static const legalNotice = '$base/en/software/vpn-android/legal/legal-notice';
  static const openSourceLicense =
      '$base/en/software/vpn-android/legal/open-source';

  static List<(String url, String slug)> docsFor(String? localeTag) => [
        (userAgreementFor(localeTag), 'user-agreement'),
        (openSourceLicenseFor(localeTag), 'open-source-license'),
        (legalNoticeFor(localeTag), 'legal-notice'),
        (disclaimerFor(localeTag), 'disclaimer'),
      ];
}
