import 'package:flutter/widgets.dart';

import '../features/connection/domain/connection_quality.dart';
import 'app_strings_de.dart';
import 'app_strings_en.dart';
import 'app_strings_es.dart';
import 'app_strings_fr.dart';
import 'app_strings_ja.dart';
import 'app_strings_ko.dart';
import 'app_strings_pt_br.dart';
import 'app_strings_zh.dart';
import 'app_strings_zh_hant.dart';

class AppLocalizations {
  AppLocalizations(this.locale);

  final Locale locale;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations) ??
        AppLocalizations(const Locale('en'));
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// 与 [localeDisplayName] / 设置内语言列表一致：简中、繁中、英、西、葡、德、法、日、韩。
  static const supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant', countryCode: 'TW'),
    Locale('es'),
    Locale('pt', 'BR'),
    Locale('de'),
    Locale('fr'),
    Locale('ja'),
    Locale('ko'),
  ];

  /// 九种语言各见独立文件 [app_strings_*.dart]（由 tool/export_app_strings_dart.py 自英文/简繁与 JSON 合并生成）。
  static final Map<String, Map<String, String>> _coreLocales = {
    'en': kAppStringsEn,
    'zh': kAppStringsZh,
    'zh_Hant': kAppStringsZhHant,
    'es': kAppStringsEs,
    'pt_BR': kAppStringsPtBr,
    'de': kAppStringsDe,
    'fr': kAppStringsFr,
    'ja': kAppStringsJa,
    'ko': kAppStringsKo,
  };

  String _value(String key) {
    String tag = locale.languageCode;
    if (locale.languageCode == 'zh') {
      if (locale.scriptCode == 'Hant' ||
          locale.countryCode == 'TW' ||
          locale.countryCode == 'HK') {
        tag = 'zh_Hant';
      } else {
        tag = 'zh';
      }
    } else if (locale.countryCode != null && locale.countryCode!.isNotEmpty) {
      final full = '${locale.languageCode}_${locale.countryCode}';
      if (_coreLocales.containsKey(full)) {
        tag = full;
      }
    }
    if (locale.scriptCode != null && locale.scriptCode!.isNotEmpty && tag == locale.languageCode) {
      final full = '${locale.languageCode}_${locale.scriptCode}';
      if (_coreLocales.containsKey(full)) {
        tag = full;
      }
    }

    if (_coreLocales.containsKey(tag) && _coreLocales[tag]!.containsKey(key)) {
      return _coreLocales[tag]![key]!;
    }
    if (tag != locale.languageCode &&
        _coreLocales.containsKey(locale.languageCode) &&
        _coreLocales[locale.languageCode]!.containsKey(key)) {
      return _coreLocales[locale.languageCode]![key]!;
    }
    return _coreLocales['en']![key] ?? key;
  }

  String get appTitle => _value('appTitle');
  String get authLegalAgreementHint => _value('authLegalAgreementHint');
  String get authLegalAgreementSeparator => _value('authLegalAgreementSeparator');
  String get settingsLegalAgreementHint => _value('settingsLegalAgreementHint');
  String get authLoginSubtitle => _value('authLoginSubtitle');
  String get authRegisterSubtitle => _value('authRegisterSubtitle');
  String get authFieldName => _value('authFieldName');
  String get authFieldEmail => _value('authFieldEmail');
  String get authFieldUsername => _value('authFieldUsername');
  String get authFieldPassword => _value('authFieldPassword');
  String get authFieldConfirmPassword => _value('authFieldConfirmPassword');
  String get authFieldVerificationCode => _value('authFieldVerificationCode');
  String get authGetCode => _value('authGetCode');
  String get authSignIn => _value('authSignIn');
  String get authSignUp => _value('authSignUp');
  String get authHaveAccount => _value('authHaveAccount');
  String get authNoAccount => _value('authNoAccount');
  String get authEnterValidEmail => _value('authEnterValidEmail');
  String get authCodeSent => _value('authCodeSent');
  String get authEnterName => _value('authEnterName');
  String get authEnterEmail => _value('authEnterEmail');
  String get authPasswordRule => _value('authPasswordRule');
  String get authPasswordMismatch => _value('authPasswordMismatch');
  String get authEnterVerificationCode => _value('authEnterVerificationCode');
  String get authEnterCredentials => _value('authEnterCredentials');
  String get authErrorInvalidEmail => _value('authErrorInvalidEmail');
  String get authErrorEmailUnreachable => _value('authErrorEmailUnreachable');
  String authErrorCodeCooldown(int seconds) =>
      _value('authErrorCodeCooldown').replaceAll('{seconds}', '$seconds');
  String get authErrorEmailTaken => _value('authErrorEmailTaken');
  String get authErrorUsernameTaken => _value('authErrorUsernameTaken');
  String get authErrorIllegalChar => _value('authErrorIllegalChar');
  String get authErrorInvalidVerificationCode =>
      _value('authErrorInvalidVerificationCode');
  String get settingsAccountTitle => _value('settingsAccountTitle');
  String get settingsLoginTitle => _value('settingsLoginTitle');
  String get settingsLoginSubtitle => _value('settingsLoginSubtitle');
  String get settingsRegisterTitle => _value('settingsRegisterTitle');
  String get settingsRegisterSubtitle => _value('settingsRegisterSubtitle');
  String get settingsAccountManageTitle => _value('settingsAccountManageTitle');
  String get settingsLogoutTitle => _value('settingsLogoutTitle');
  String get accountChangePassword => _value('accountChangePassword');
  String get accountChangeName => _value('accountChangeName');
  String get accountChangeEmail => _value('accountChangeEmail');
  String get accountFeedbackAdmin => _value('accountFeedbackAdmin');
  String get accountFeedbackTicket => _value('accountFeedbackTicket');
  String get accountContactUs => _value('accountContactUs');
  String get accountAboutUs => _value('accountAboutUs');
  String get accountLogout => _value('accountLogout');
  String get accountLogoutConfirm => _value('accountLogoutConfirm');
  String get accountOldPassword => _value('accountOldPassword');
  String get accountNewPassword => _value('accountNewPassword');
  String get accountConfirmPassword => _value('accountConfirmPassword');
  String get accountForgotPassword => _value('accountForgotPassword');
  String get accountEmail => _value('accountEmail');
  String get accountVerificationCode => _value('accountVerificationCode');
  String get accountSendCode => _value('accountSendCode');
  String accountResendIn(int seconds) =>
      _value('accountResendIn').replaceAll('{seconds}', '$seconds');
  String get accountCurrentName => _value('accountCurrentName');
  String get accountNewName => _value('accountNewName');
  String get accountCurrentEmail => _value('accountCurrentEmail');
  String get accountNewEmail => _value('accountNewEmail');
  String get accountVerifyPassword => _value('accountVerifyPassword');
  String get accountSave => _value('accountSave');
  String get accountUpdateSuccess => _value('accountUpdateSuccess');
  String get accountPasswordMismatch => _value('accountPasswordMismatch');
  String get accountPasswordTooShort => _value('accountPasswordTooShort');
  String get accountInvalidEmail => _value('accountInvalidEmail');
  String get accountCodeSent => _value('accountCodeSent');
  String get accountCodeRequired => _value('accountCodeRequired');
  String get accountLoginRequired => _value('accountLoginRequired');
  String get accountRefreshFailed => _value('accountRefreshFailed');
  String get accountOpenWebsiteFailed => _value('accountOpenWebsiteFailed');
  String get accountThrottledHint => _value('accountThrottledHint');
  String get accountQuotaTitle => _value('accountQuotaTitle');
  String accountQuotaSummary(double quotaGb, double usedGb, double percent) =>
      _value('accountQuotaSummary')
          .replaceAll('{quotaGb}', quotaGb.toStringAsFixed(0))
          .replaceAll('{usedGb}', usedGb.toStringAsFixed(2))
          .replaceAll('{percent}', percent.toStringAsFixed(0));
  String get accountFeedbackAdminBody => _value('accountFeedbackAdminBody');
  String accountFeedbackLogSize(String size) =>
      _value('accountFeedbackLogSize').replaceAll('{size}', size);
  String accountFeedbackDataUsage(int kb) =>
      _value('accountFeedbackDataUsage').replaceAll('{kb}', '$kb');
  String get accountFeedbackConfirm => _value('accountFeedbackConfirm');
  String get accountFeedbackDecline => _value('accountFeedbackDecline');
  String get accountFeedbackSubmitted => _value('accountFeedbackSubmitted');
  String get accountFeedbackFailed => _value('accountFeedbackFailed');
  String get ticketTypeLabel => _value('ticketTypeLabel');
  String get ticketTypePageBug => _value('ticketTypePageBug');
  String get ticketTypeSoftwareBug => _value('ticketTypeSoftwareBug');
  String get ticketTypeOther => _value('ticketTypeOther');
  String get ticketTypeOtherHint => _value('ticketTypeOtherHint');
  String get ticketSeverityLabel => _value('ticketSeverityLabel');
  String get ticketSeverityLow => _value('ticketSeverityLow');
  String get ticketSeverityMedium => _value('ticketSeverityMedium');
  String get ticketSeverityHigh => _value('ticketSeverityHigh');
  String get ticketSeverityCritical => _value('ticketSeverityCritical');
  String get ticketContactEmail => _value('ticketContactEmail');
  String get ticketContactEmailHint => _value('ticketContactEmailHint');
  String get ticketDescription => _value('ticketDescription');
  String get ticketDescriptionRequired => _value('ticketDescriptionRequired');
  String get ticketAddImages => _value('ticketAddImages');
  String ticketImagesLimit(int count) =>
      _value('ticketImagesLimit').replaceAll('{count}', '$count');
  String get ticketSubmit => _value('ticketSubmit');
  String get ticketSubmitted => _value('ticketSubmitted');
  String get settingsSectionTrafficRouting =>
      _value('settingsSectionTrafficRouting');
  String get settingsSectionDnsNetwork => _value('settingsSectionDnsNetwork');
  String get settingsPendingVpnApproval => _value('settingsPendingVpnApproval');
  String get homeNoNodesAvailable => _value('homeNoNodesAvailable');
  String get homeServerTimeoutLabel => _value('homeServerTimeoutLabel');
  String get homeNoticeTitle => _value('homeNoticeTitle');
  String get homeTrafficUsageTitle => _value('homeTrafficUsageTitle');
  String get homeTrafficUsageLowMessage => _value('homeTrafficUsageLowMessage');
  String get homeLoginVpnRequired => _value('homeLoginVpnRequired');
  String get connect => _value('connect');
  String get disconnect => _value('disconnect');
  String get cancel => _value('cancel');
  String get tapToCancel => _value('tapToCancel');
  String get watchAdToStart => _value('watchAdToStart');
  String get pleaseSelectServer => _value('pleaseSelectServer');
  String get locations => _value('locations');
  String get viewAll => _value('viewAll');
  String get serverDownloadLabel => _value('serverDownloadLabel');
  String get serverUploadLabel => _value('serverUploadLabel');
  String serverSessionsLabel(int count) {
    final key =
        count == 1 ? 'serverSessionsSingular' : 'serverSessionsPlural';
    return _value(key).replaceAll('{count}', '$count');
  }
  String get searchLocations => _value('searchLocations');
  String showingLocations(int visible, int total) {
    return _value('showingLocations')
        .replaceAll('{visible}', '$visible')
        .replaceAll('{total}', '$total');
  }

  String noLocationsMatch(String query) {
    return _value('noLocationsMatch').replaceAll('{query}', query);
  }

  String get failedToLoadServers => _value('failedToLoadServers');
  String get serverListHintConnectFirst => _value('serverListHintConnectFirst');
  String get termsPrivacy => _value('termsPrivacy');
  String get currentIp => _value('currentIp');
  String get networkLocation => _value('networkLocation');
  String get networkIsp => _value('networkIsp');
  String get networkTimezone => _value('networkTimezone');
  String get sessionLabel => _value('session');
  String get runSpeedTest => _value('runSpeedTest');
  String get legalTitle => _value('legalTitle');
  String get legalBody => _value('legalBody');
  String get close => _value('close');
  String get sessionExpiredTitle => _value('sessionExpiredTitle');
  String get sessionExpiredBody => _value('sessionExpiredBody');
  String get ok => _value('ok');
  String get disconnectedWatchAd => _value('disconnectedWatchAd');
  String get statusConnected => _value('statusConnected');
  String get statusConnecting => _value('statusConnecting');
  String get statusPreparing => _value('statusPreparing');
  String get statusError => _value('statusError');
  String get statusDisconnected => _value('statusDisconnected');
  String get selectServerToBegin => _value('selectServerToBegin');
  String get unlockSecureAccess => _value('unlockSecureAccess');
  String get sessionRemaining => _value('sessionRemaining');
  String get noServerSelected => _value('noServerSelected');
  String get serverNoNodes => _value('serverNoNodes');
  String get latencyLabel => _value('latencyLabel');
  String get badgeConnected => _value('badgeConnected');
  String get badgeSelected => _value('badgeSelected');
  String get badgeConnect => _value('badgeConnect');
  String get tutorialChooseLocation => _value('tutorialChooseLocation');
  String get tutorialWatchAd => _value('tutorialWatchAd');
  String get tutorialSession => _value('tutorialSession');
  String get tutorialSpeed => _value('tutorialSpeed');
  String get tutorialSkip => _value('tutorialSkip');
  String get connectionQualityTitle => _value('connectionQualityTitle');
  String get connectionQualityRefresh => _value('connectionQualityRefresh');
  String get homeWidgetTitle => _value('homeWidgetTitle');
  String get settingsTitle => _value('settingsTitle');
  String get settingsConnection => _value('settingsConnection');
  String get settingsSectionKeepAlive => _value('settingsSectionKeepAlive');
  String get settingsBatteryExemption => _value('settingsBatteryExemption');
  String get settingsBatteryExemptionSubtitle =>
      _value('settingsBatteryExemptionSubtitle');
  String get settingsBatteryExemptionAlready =>
      _value('settingsBatteryExemptionAlready');
  String get settingsBatteryExemptionSet =>
      _value('settingsBatteryExemptionSet');
  String get settingsAutoConnectOnLaunch =>
      _value('settingsAutoConnectOnLaunch');
  String get settingsAutoConnectOnLaunchSubtitle =>
      _value('settingsAutoConnectOnLaunchSubtitle');
  String get settingsReconnectOnNetworkChange =>
      _value('settingsReconnectOnNetworkChange');
  String get settingsReconnectOnNetworkChangeSubtitle =>
      _value('settingsReconnectOnNetworkChangeSubtitle');
  String get settingsConnectOnBoot => _value('settingsConnectOnBoot');
  String get settingsConnectOnBootSubtitle =>
      _value('settingsConnectOnBootSubtitle');
  String get settingsTrafficMode => _value('settingsTrafficMode');
  String get settingsTrafficModeGlobal => _value('settingsTrafficModeGlobal');
  String get settingsTrafficModeGlobalSubtitle =>
      _value('settingsTrafficModeGlobalSubtitle');
  String get settingsTrafficModeRule => _value('settingsTrafficModeRule');
  String get settingsTrafficModeRuleSubtitle =>
      _value('settingsTrafficModeRuleSubtitle');
  String get settingsTrafficModeAuto => _value('settingsTrafficModeAuto');
  String get settingsTrafficModeAutoHint => _value('settingsTrafficModeAutoHint');
  String get settingsRuleEditorEmptyHint => _value('settingsRuleEditorEmptyHint');
  String settingsRuleEditorRuleCount(int count) =>
      _value('settingsRuleEditorRuleCount').replaceAll('{count}', '$count');
  String get settingsDnsServer => _value('settingsDnsServer');
  String get settingsDnsCloudflare => _value('settingsDnsCloudflare');
  String get settingsDnsGoogle => _value('settingsDnsGoogle');
  String get settingsDnsCustom => _value('settingsDnsCustom');
  String get settingsNetworkQuality => _value('settingsNetworkQuality');
  String get settingsNetworkQualitySubtitle =>
      _value('settingsNetworkQualitySubtitle');
  String get settingsBatterySaver => _value('settingsBatterySaver');
  String get settingsBatterySaverSubtitle =>
      _value('settingsBatterySaverSubtitle');
  String get settingsLogRetentionNote => _value('settingsLogRetentionNote');
  String get settingsSectionNetwork => _value('settingsSectionNetwork');
  String get settingsSectionDiagnostics => _value('settingsSectionDiagnostics');
  String get settingsSectionSecurity => _value('settingsSectionSecurity');
  String get settingsSectionAppRouting => _value('settingsSectionAppRouting');
  String get settingsSectionProtocol => _value('settingsSectionProtocol');
  String get settingsSectionProxyShare => _value('settingsSectionProxyShare');
  String get settingsKillSwitch => _value('settingsKillSwitch');
  String get settingsKillSwitchOff => _value('settingsKillSwitchOff');
  String get settingsKillSwitchStrict => _value('settingsKillSwitchStrict');
  String get settingsKillSwitchSmart => _value('settingsKillSwitchSmart');
  String get settingsForceDnsThroughTunnel =>
      _value('settingsForceDnsThroughTunnel');
  String get settingsForceDnsThroughTunnelSubtitle =>
      _value('settingsForceDnsThroughTunnelSubtitle');
  String get settingsBlockLocalDns => _value('settingsBlockLocalDns');
  String get settingsBlockLocalDnsSubtitle =>
      _value('settingsBlockLocalDnsSubtitle');
  String get settingsBlockIpv6Dns => _value('settingsBlockIpv6Dns');
  String get settingsBlockIpv6DnsSubtitle =>
      _value('settingsBlockIpv6DnsSubtitle');
  String get settingsDisableIpv6 => _value('settingsDisableIpv6');
  String get settingsDisableIpv6Subtitle =>
      _value('settingsDisableIpv6Subtitle');
  String get settingsAppSplitMode => _value('settingsAppSplitMode');
  String get settingsAppSplitOff => _value('settingsAppSplitOff');
  String get settingsAppSplitInclude => _value('settingsAppSplitInclude');
  String get settingsAppSplitExclude => _value('settingsAppSplitExclude');
  String settingsAppSplitAppCount(int count) =>
      _value('settingsAppSplitAppCount').replaceAll('{count}', '$count');
  String get settingsAppSelectApps => _value('settingsAppSelectApps');
  String get settingsAppSelectAppsSubtitle =>
      _value('settingsAppSelectAppsSubtitle');
  String get settingsTunnelMode => _value('settingsTunnelMode');
  String get settingsTunnelModeTun => _value('settingsTunnelModeTun');
  String get settingsTunnelModeSystemProxy =>
      _value('settingsTunnelModeSystemProxy');
  String get settingsTransportProtocol => _value('settingsTransportProtocol');
  String get settingsProtocolWireGuard => _value('settingsProtocolWireGuard');
  String get settingsProtocolOpenVpn => _value('settingsProtocolOpenVpn');
  String get settingsProtocolRealityVless =>
      _value('settingsProtocolRealityVless');
  String get settingsProtocolHysteria2 => _value('settingsProtocolHysteria2');
  String get settingsProtocolTuic => _value('settingsProtocolTuic');
  String get settingsProtocolComingSoon => _value('settingsProtocolComingSoon');
  String get settingsProxyShare => _value('settingsProxyShare');
  String get settingsProxyShareSubtitle => _value('settingsProxyShareSubtitle');
  String get settingsProxyShareMode => _value('settingsProxyShareMode');
  String get settingsProxyShareHttp => _value('settingsProxyShareHttp');
  String get settingsProxyShareSocks5 => _value('settingsProxyShareSocks5');
  String get settingsProxyShareLan => _value('settingsProxyShareLan');
  String settingsLimitHelperServerMax(String maxGb) =>
      _value('settingsLimitHelperServerMax').replaceAll('{maxGb}', maxGb);
  String get settingsLimitHelperDefault => _value('settingsLimitHelperDefault');
  String get settingsLimitErrorMinMb => _value('settingsLimitErrorMinMb');
  String get settingsLimitErrorExceedsServer =>
      _value('settingsLimitErrorExceedsServer');
  String get settingsLimitErrorExceedsMax => _value('settingsLimitErrorExceedsMax');
  String get settingsRuleSource => _value('settingsRuleSource');
  String get settingsRuleSourceBuiltIn => _value('settingsRuleSourceBuiltIn');
  String get settingsRuleSourceBuiltInSubtitle =>
      _value('settingsRuleSourceBuiltInSubtitle');
  String get settingsRuleSourceCustom => _value('settingsRuleSourceCustom');
  String get settingsRuleSourceCustomSubtitle =>
      _value('settingsRuleSourceCustomSubtitle');
  String get settingsRuleEditor => _value('settingsRuleEditor');
  String get settingsRuleEditorHint => _value('settingsRuleEditorHint');
  String get settingsRuleDomains => _value('settingsRuleDomains');
  String get settingsRuleDomainsSubtitle =>
      _value('settingsRuleDomainsSubtitle');
  String get settingsSectionLegal => _value('settingsSectionLegal');
  String get settingsLegalLinkText => _value('settingsLegalLinkText');
  String get settingsSectionLanguage => _value('settingsSectionLanguage');
  String get settingsSectionAppearance => _value('settingsSectionAppearance');
  String get settingsSectionTheme => _value('settingsSectionTheme');
  String get settingsSectionLogs => _value('settingsSectionLogs');
  String get settingsLogEnabled => _value('settingsLogEnabled');
  String get settingsLogEnabledSubtitle => _value('settingsLogEnabledSubtitle');
  String get settingsClearLogs => _value('settingsClearLogs');
  String get settingsClearLogsSubtitle => _value('settingsClearLogsSubtitle');
  String get settingsClearLogsDone => _value('settingsClearLogsDone');
  String get settingsSnackbarPending => _value('settingsSnackbarPending');
  String get settingsLogLevel => _value('settingsLogLevel');
  String get settingsLogPath => _value('settingsLogPath');
  String get settingsLogPathLoading => _value('settingsLogPathLoading');
  String get settingsLogPathCopied => _value('settingsLogPathCopied');
  String get settingsLogPathOpened => _value('settingsLogPathOpened');
  String get settingsLogSizeLimit => _value('settingsLogSizeLimit');
  String get settingsLogCountLimit => _value('settingsLogCountLimit');
  String get legalDocsTitle => _value('legalDocsTitle');
  String get legalUserAgreement => _value('legalUserAgreement');
  String get legalOpenSource => _value('legalOpenSource');
  String get legalNotice => _value('legalNotice');
  String get legalDisclaimer => _value('legalDisclaimer');
  String get dashboardWebsiteTest => _value('dashboardWebsiteTest');
  String get dashboardQuickTest => _value('dashboardQuickTest');
  String get dashboardIpInfo => _value('dashboardIpInfo');
  String get dashboardRefresh => _value('dashboardRefresh');
  String get dashboardAsn => _value('dashboardAsn');
  String get dashboardAutoRefresh => _value('dashboardAutoRefresh');
  String get dashboardIsp => _value('dashboardIsp');
  String get dashboardOrg => _value('dashboardOrg');
  String get dashboardFetchFailed => _value('dashboardFetchFailed');
  String get dashboardParseFailed => _value('dashboardParseFailed');
  String get dashboardTrafficTrend => _value('dashboardTrafficTrend');
  String get dashboardTrafficHint => _value('dashboardTrafficHint');
  String get dashboardLabelUpload => _value('dashboardLabelUpload');
  String get dashboardLabelDownload => _value('dashboardLabelDownload');
  String get dashboardLabelMemory => _value('dashboardLabelMemory');
  String get dashboardLabelDownloadTotal => _value('dashboardLabelDownloadTotal');
  String get dashboardLabelUploadTotal => _value('dashboardLabelUploadTotal');
  String get dashboardUsageStats => _value('dashboardUsageStats');
  String get dashboardPeriodToday => _value('dashboardPeriodToday');
  String get dashboardPeriodWeek => _value('dashboardPeriodWeek');
  String get dashboardPeriodMonth => _value('dashboardPeriodMonth');
  String get dashboardPeriodYear => _value('dashboardPeriodYear');
  String get dashboardPeriodAll => _value('dashboardPeriodAll');
  String get dashboardPeriodTitle => _value('dashboardPeriodTitle');
  String get dashboardPeriod1Day => _value('dashboardPeriod1Day');
  String get dashboardPeriod1Week => _value('dashboardPeriod1Week');
  String get dashboardPeriod1Month => _value('dashboardPeriod1Month');
  String get dashboardPeriod1Year => _value('dashboardPeriod1Year');
  String get dashboardTest => _value('dashboardTest');
  String get dashboardTimeout => _value('dashboardTimeout');
  String get dashboardFailed => _value('dashboardFailed');
  String get dashboardUsedToday => _value('dashboardUsedToday');
  String get dashboardUsedWeek => _value('dashboardUsedWeek');
  String get dashboardUsedMonth => _value('dashboardUsedMonth');
  String get dashboardUsedYear => _value('dashboardUsedYear');
  String get dashboardUsedAll => _value('dashboardUsedAll');
  String get settingsSectionRouting => _value('settingsSectionRouting');
  String get settingsAutoRoute => _value('settingsAutoRoute');
  String get settingsAutoRouteSubtitle => _value('settingsAutoRouteSubtitle');
  String get settingsBypassLan => _value('settingsBypassLan');
  String get settingsBypassLanSubtitle => _value('settingsBypassLanSubtitle');
  String get settingsSelectApps => _value('settingsSelectApps');
  String get settingsSelectAppsSubtitle => _value('settingsSelectAppsSubtitle');
  String get settingsSelectAppsPending => _value('settingsSelectAppsPending');
  String get settingsSectionDns => _value('settingsSectionDns');
  String get settingsDnsHijack => _value('settingsDnsHijack');
  String get settingsDnsHijackSubtitle => _value('settingsDnsHijackSubtitle');
  String get settingsNameServerPolicy => _value('settingsNameServerPolicy');
  String get settingsDnsPolicy => _value('settingsDnsPolicy');
  String get settingsForceResolve => _value('settingsForceResolve');
  String get settingsForceResolveSubtitle => _value('settingsForceResolveSubtitle');
  String get settingsForceDnsMapping => _value('settingsForceDnsMapping');
  String get settingsForceDnsMappingSubtitle => _value('settingsForceDnsMappingSubtitle');
  String get settingsResolvePureIp => _value('settingsResolvePureIp');
  String get settingsResolvePureIpSubtitle => _value('settingsResolvePureIpSubtitle');
  String get settingsFakeipFilter => _value('settingsFakeipFilter');
  String get settingsFakeipFilterSubtitle => _value('settingsFakeipFilterSubtitle');
  String get settingsSectionAdvanced => _value('settingsSectionAdvanced');
  String get settingsStackMode => _value('settingsStackMode');
  String get settingsStackModeSubtitle => _value('settingsStackModeSubtitle');
  String get settingsH3Priority => _value('settingsH3Priority');
  String get settingsH3PrioritySubtitle => _value('settingsH3PrioritySubtitle');
  String get settingsTlsSniffOverride => _value('settingsTlsSniffOverride');
  String get settingsTlsSniffOverrideSubtitle => _value('settingsTlsSniffOverrideSubtitle');
  String get settingsTcpConcurrent => _value('settingsTcpConcurrent');
  String get settingsTcpConcurrentSubtitle => _value('settingsTcpConcurrentSubtitle');
  String get settingsAutoSwitch => _value('settingsAutoSwitch');
  String get settingsAutoSwitchSubtitle => _value('settingsAutoSwitchSubtitle');
  String get settingsHaptics => _value('settingsHaptics');
  String get settingsHapticsSubtitle => _value('settingsHapticsSubtitle');
  String get settingsPreciseSessionTimer => _value('settingsPreciseSessionTimer');
  String get settingsPreciseSessionTimerSubtitle =>
      _value('settingsPreciseSessionTimerSubtitle');
  String get settingsUsage => _value('settingsUsage');
  String get settingsUsageSubtitle => _value('settingsUsageSubtitle');
  String get settingsUsageLimit => _value('settingsUsageLimit');
  String get settingsUsageNoLimit => _value('settingsUsageNoLimit');
  String get settingsSetLimit => _value('settingsSetLimit');
  String get settingsResetUsage => _value('settingsResetUsage');
  String get settingsRemoveLimit => _value('settingsRemoveLimit');
  String get settingsBackup => _value('settingsBackup');
  String get settingsCreateBackup => _value('settingsCreateBackup');
  String get settingsRestore => _value('settingsRestore');
  String get settingsReferral => _value('settingsReferral');
  String get settingsReferralSubtitle => _value('settingsReferralSubtitle');
  String get settingsAddReferral => _value('settingsAddReferral');
  String get settingsLanguage => _value('settingsLanguage');
  String get settingsLanguageSubtitle => _value('settingsLanguageSubtitle');
  String get settingsLanguageSystem => _value('settingsLanguageSystem');
  String get settingsAppearance => _value('settingsAppearance');
  String get settingsAppearanceSubtitle => _value('settingsAppearanceSubtitle');
  String get settingsThemeSystem => _value('settingsThemeSystem');
  String get settingsThemeLight => _value('settingsThemeLight');
  String get settingsThemeDark => _value('settingsThemeDark');
  String get settingsReferralHint => _value('settingsReferralHint');
  String get settingsLimitHint => _value('settingsLimitHint');
  String get settingsLimitHelper => _value('settingsLimitHelper');
  String get settingsLimitErrorEmpty => _value('settingsLimitErrorEmpty');
  String get settingsLimitErrorInvalid => _value('settingsLimitErrorInvalid');
  String get settingsRewards => _value('settingsRewards');
  String get settingsLegal => _value('settingsLegal');
  String get settingsPrivacyPolicy => _value('settingsPrivacyPolicy');
  String get settingsPrivacyPolicySubtitle =>
      _value('settingsPrivacyPolicySubtitle');
  String get snackbarBackupCopied => _value('snackbarBackupCopied');
  String get snackbarRestoreComplete => _value('snackbarRestoreComplete');
  String get snackbarRestoreFailed => _value('snackbarRestoreFailed');
  String get snackbarReferralAdded => _value('snackbarReferralAdded');
  String get snackbarLimitSaved => _value('snackbarLimitSaved');
  String get adFailedToLoad => _value('adFailedToLoad');
  String get adNotReady => _value('adNotReady');
  String get adFailedToShow => _value('adFailedToShow');
  String get adMustComplete => _value('adMustComplete');
  String get navHome => _value('navHome');
  String get navSpeedTest => _value('navSpeedTest');
  String get navHistory => _value('navHistory');
  String get navDashboard => _value('navDashboard');
  String get navSettings => _value('navSettings');
  String get serverLatencyTimeout => _value('serverLatencyTimeout');
  String get serverLatencyNoNodes => _value('serverLatencyNoNodes');
  String get serverPinnedHk => _value('serverPinnedHk');
  String get serverPinnedUs => _value('serverPinnedUs');
  String get serverPinnedSg => _value('serverPinnedSg');
  String get geoCityHongKong => _value('geoCityHongKong');
  String get geoCityLosAngeles => _value('geoCityLosAngeles');
  String get geoCitySingapore => _value('geoCitySingapore');
  String get serverTileHostPrefix => _value('serverTileHostPrefix');
  String get serverTileIpPrefix => _value('serverTileIpPrefix');
  String get serverTilePingPrefix => _value('serverTilePingPrefix');
  String get serverTileDownPrefix => _value('serverTileDownPrefix');
  String get serverTileUpPrefix => _value('serverTileUpPrefix');
  String get serverTileSessionsPrefix => _value('serverTileSessionsPrefix');
  String get privacyPolicyDialogTitle => _value('privacyPolicyDialogTitle');
  String get privacyPolicyAgreeButton => _value('privacyPolicyAgreeButton');
  String get privacyPolicyCheckboxLabel =>
      _value('privacyPolicyCheckboxLabel');
  String get privacyPolicyAvailableInSettings =>
      _value('privacyPolicyAvailableInSettings');
  String get privacyPolicyScrollHintAction =>
      _value('privacyPolicyScrollHintAction');
  String get privacyPolicyScrollHint => _value('privacyPolicyScrollHint');
  String get privacyPolicyScrollWarning =>
      _value('privacyPolicyScrollWarning');
  String get privacyPolicyAgreementRequired =>
      _value('privacyPolicyAgreementRequired');
  String get privacyPolicyCheckboxReady =>
      _value('privacyPolicyCheckboxReady');
  String get speedTestCardTitle => _value('speedTestCardTitle');
  String get speedTestCardStart => _value('speedTestCardStart');
  String get speedTestCardRetest => _value('speedTestCardRetest');
  String get speedTestCardTesting => _value('speedTestCardTesting');
  String get speedTestCardLocating => _value('speedTestCardLocating');
  String get speedTestCardDownloadWarmup =>
      _value('speedTestCardDownloadWarmup');
  String get speedTestCardDownloadMeasure =>
      _value('speedTestCardDownloadMeasure');
  String get speedTestCardUploadWarmup =>
      _value('speedTestCardUploadWarmup');
  String get speedTestCardUploadMeasure =>
      _value('speedTestCardUploadMeasure');
  String get speedTestCardComplete => _value('speedTestCardComplete');
  String get speedTestCardError => _value('speedTestCardError');
  String get speedTestCardDownloadLabel =>
      _value('speedTestCardDownloadLabel');
  String get speedTestCardUploadLabel =>
      _value('speedTestCardUploadLabel');
  String get speedTestCardLatencyLabel =>
      _value('speedTestCardLatencyLabel');
  String get speedTestCardLossLabel => _value('speedTestCardLossLabel');
  String get speedTestCardServerLabel => _value('speedTestCardServerLabel');
  String get speedTestErrorTimeout => _value('speedTestErrorTimeout');
  String get speedTestErrorToken => _value('speedTestErrorToken');
  String get speedTestErrorTls => _value('speedTestErrorTls');
  String get speedTestErrorNoResult => _value('speedTestErrorNoResult');
  String get speedTestErrorGeneric => _value('speedTestErrorGeneric');
  String get speedTestMeasuring => _value('speedTestMeasuring');
  String get speedTestPending => _value('speedTestPending');
  String get speedTestDetecting => _value('speedTestDetecting');
  String get speedTestNotAvailable => _value('speedTestNotAvailable');
  String get speedTestBenchmarking => _value('speedTestBenchmarking');
  String get speedTestBenchmarkingLocal => _value('speedTestBenchmarkingLocal');
  String get speedTestPreparingTunnel => _value('speedTestPreparingTunnel');
  String get speedTestPreparingLocal => _value('speedTestPreparingLocal');
  String get speedTestResultIntro => _value('speedTestResultIntro');
  String get speedTestErrorIntro => _value('speedTestErrorIntro');
  String get speedTestIdleIntro => _value('speedTestIdleIntro');
  String get speedTestPreparingShort => _value('speedTestPreparingShort');
  String get speedTestResult => _value('speedTestResult');
  String get speedTestCompleted => _value('speedTestCompleted');
  String get speedTestTapRetry => _value('speedTestTapRetry');
  String get speedTestReady => _value('speedTestReady');
  String get speedTestRunAgain => _value('speedTestRunAgain');
  String get speedTestRetryTest => _value('speedTestRetryTest');
  String get speedTestStartTest => _value('speedTestStartTest');
  String get speedTestCheckLatency => _value('speedTestCheckLatency');
  String get speedTestCollecting => _value('speedTestCollecting');
  String get speedTestRunToGetValues => _value('speedTestRunToGetValues');
  String get speedTestResultsOverview => _value('speedTestResultsOverview');
  String get speedTestNoData => _value('speedTestNoData');
  String get speedTestWhatLooksGood => _value('speedTestWhatLooksGood');
  String get speedTestCouldBeBetter => _value('speedTestCouldBeBetter');
  String get speedTestIpLabel => _value('speedTestIpLabel');
  String get speedTestInsightDownloadExcellent => _value('speedTestInsightDownloadExcellent');
  String get speedTestInsightDownloadHd => _value('speedTestInsightDownloadHd');
  String get speedTestInsightDownloadStruggle => _value('speedTestInsightDownloadStruggle');
  String get speedTestInsightUploadGood => _value('speedTestInsightUploadGood');
  String get speedTestInsightUploadImpact => _value('speedTestInsightUploadImpact');
  String get speedTestInsightLatencyLow => _value('speedTestInsightLatencyLow');
  String get speedTestInsightLatencyReasonable => _value('speedTestInsightLatencyReasonable');
  String get speedTestInsightLatencyHigh => _value('speedTestInsightLatencyHigh');
  String get speedTestInsightIpDetected => _value('speedTestInsightIpDetected');
  String get speedTestInsightIpNotDetected => _value('speedTestInsightIpNotDetected');
  String speedTestNetworkScoreLabel(int score) =>
      _value('speedTestNetworkScoreLabel').replaceAll('{score}', '$score');

  String get gameDecelSectionTitle => _value('gameDecelSectionTitle');
  String get gameDecelTierLow => _value('gameDecelTierLow');
  String get gameDecelTierMedium => _value('gameDecelTierMedium');
  String get gameDecelTierHigh => _value('gameDecelTierHigh');
  String get gameDecelTierUltra => _value('gameDecelTierUltra');
  String get gameDecelTooltipHelp => _value('gameDecelTooltipHelp');
  String get gameDecelInfoLowBody => _value('gameDecelInfoLowBody');
  String get gameDecelInfoMediumBody => _value('gameDecelInfoMediumBody');
  String get gameDecelInfoHighBody => _value('gameDecelInfoHighBody');
  String get gameDecelInfoUltraBody => _value('gameDecelInfoUltraBody');
  String get gameDecelInfoOk => _value('gameDecelInfoOk');
  String get gameModeSettingsTitle => _value('gameModeSettingsTitle');
  String get gameModeBackTooltip => _value('gameModeBackTooltip');
  String get gameModeMenuTooltip => _value('gameModeMenuTooltip');
  String get gameModeDecelMode => _value('gameModeDecelMode');
  String get gameModeAccelMode => _value('gameModeAccelMode');

  String connectionQualityLabel(ConnectionQuality quality) {
    switch (quality) {
      case ConnectionQuality.excellent:
        return _value('connectionQualityExcellent');
      case ConnectionQuality.good:
        return _value('connectionQualityGood');
      case ConnectionQuality.fair:
        return _value('connectionQualityFair');
      case ConnectionQuality.poor:
        return _value('connectionQualityPoor');
      case ConnectionQuality.offline:
        return _value('connectionQualityOffline');
    }
  }

  String connectionQualityMetrics({
    required double download,
    required double upload,
    required int ping,
  }) {
    return '↓ ${download.toStringAsFixed(1)} Mbps · ↑ ${upload.toStringAsFixed(1)} Mbps · ${ping}ms';
  }

  String connectedCountdownLabel(String countdown) {
    return '${_value('statusConnected')}: $countdown';
  }

  String homeWidgetSessionRemaining(String remaining) {
    return '${_value('sessionRemaining')}: $remaining';
  }

  String homeWidgetQualitySummary(String qualityLabel) {
    return '${_value('connectionQualityTitle')}: $qualityLabel';
  }

  String usageSummaryText(double usedGb, double? limitGb) {
    final used = usedGb.toStringAsFixed(2);
    if (limitGb == null) {
      return '$used GB · ${settingsUsageNoLimit}';
    }
    final limit = limitGb.toStringAsFixed(2);
    return '$used GB / $limit GB';
  }

  String sessionElapsedLabel(String duration) =>
      _value('sessionElapsedLabel').replaceAll('{duration}', duration);

  String sessionElapsedParts({
    int? day,
    required int hour,
    required int minute,
    required int second,
    int? millisecond,
  }) {
    final parts = <String>[];
    if (day != null) {
      parts.add(_value('sessionUnitDay').replaceAll('{n}', '$day'));
    }
    parts.add(_value('sessionUnitHour').replaceAll('{n}', '$hour'));
    parts.add(_value('sessionUnitMinute').replaceAll('{n}', '$minute'));
    parts.add(_value('sessionUnitSecond').replaceAll('{n}', '$second'));
    if (millisecond != null) {
      parts.add(
        _value('sessionUnitMillisecond').replaceAll(
          '{n}',
          millisecond.toString().padLeft(3, '0'),
        ),
      );
    }
    return parts.join(' ');
  }
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    final l = locale.languageCode;
    if (l == 'en' ||
        l == 'ja' ||
        l == 'ko' ||
        l == 'es' ||
        l == 'de' ||
        l == 'fr') {
      return true;
    }
    if (l == 'pt') {
      return true;
    }
    if (l == 'zh') {
      return true;
    }
    return false;
  }

  @override
  Future<AppLocalizations> load(Locale locale) async {
    return AppLocalizations(locale);
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
