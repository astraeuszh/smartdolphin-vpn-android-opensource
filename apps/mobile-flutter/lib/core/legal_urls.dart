/// Central legal documents, hosted only on docs.smartdolphinvpn.com.
class LegalUrls {
  LegalUrls._();

  static const base = 'https://docs.smartdolphinvpn.com';

  /// Map app locale tag → doc site language path segment.
  static String docLangFor(String? localeTag) {
    switch (localeTag) {
      case 'zh':
      case 'zh-CN':
        return 'zh-CN';
      case 'zh_Hant_TW':
      case 'zh-Hant':
      case 'zh-Hant-TW':
      case 'zh-TW':
        return 'zh-TW';
      case 'ja':
        return 'ja';
      case 'es':
        return 'es';
      default:
        return 'en';
    }
  }

  static String _page(String id, String? localeTag) =>
      '$base/?lang=${docLangFor(localeTag)}#$id';

  static String userAgreementFor(String? localeTag) =>
      _page('legal-user-agreement', localeTag);
  static String serviceTermsFor(String? localeTag) =>
      _page('legal-service-terms', localeTag);
  static String privacyPolicyFor(String? localeTag) =>
      _page('legal-privacy-policy', localeTag);
  static String cookiePolicyFor(String? localeTag) =>
      _page('legal-cookie-policy', localeTag);
  static String communityRulesFor(String? localeTag) =>
      _page('legal-community-rules', localeTag);
  static String violationPolicyFor(String? localeTag) =>
      _page('legal-violation-policy', localeTag);
  static String disclaimerFor(String? localeTag) =>
      _page('legal-disclaimer', localeTag);
  static String legalNoticeFor(String? localeTag) =>
      _page('legal-disclaimer', localeTag);
  static String openSourceLicenseFor(String? localeTag) =>
      _page('legal-open-source', localeTag);

  static const sdrlTutorialZh = '$base/#protocol-0';
  static const sdrlTutorialEn = '$base/#protocol-0';

  static String sdrlTutorialFor(String? localeTag) =>
      docLangFor(localeTag) == 'zh-CN' ? sdrlTutorialZh : sdrlTutorialEn;

  static List<(String url, String slug)> docsFor(String? localeTag) => [
        (userAgreementFor(localeTag), 'user-agreement'),
        (serviceTermsFor(localeTag), 'service-terms'),
        (privacyPolicyFor(localeTag), 'privacy-policy'),
        (cookiePolicyFor(localeTag), 'cookie-policy'),
        (communityRulesFor(localeTag), 'community-rules'),
        (violationPolicyFor(localeTag), 'violation-policy'),
        (openSourceLicenseFor(localeTag), 'open-source-license'),
        (disclaimerFor(localeTag), 'disclaimer'),
      ];
}
