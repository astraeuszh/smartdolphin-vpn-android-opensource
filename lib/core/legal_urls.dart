/// Central legal document URLs hosted at doc.smartdolphin.top
class LegalUrls {
  LegalUrls._();

  static const base = 'https://doc.smartdolphin.top';

  static const userAgreement = '$base/user-agreement.html';
  static const disclaimer = '$base/disclaimer.html';
  static const legalNotice = '$base/legal-notice.html';
  static const openSourceLicense = '$base/open-source-license.html';

  static const docs = <(String, String)>[
    (userAgreement, 'user-agreement'),
    (openSourceLicense, 'open-source-license'),
    (legalNotice, 'legal-notice'),
    (disclaimer, 'disclaimer'),
  ];
}
