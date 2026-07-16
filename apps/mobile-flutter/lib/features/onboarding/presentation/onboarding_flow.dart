import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app_settings/app_settings.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../l10n/app_localizations.dart';
import '../../../core/platform/runtime_platform.dart';
import '../../../services/analytics/analytics_service.dart';
import '../../../services/notifications/session_notification_service.dart';
import '../../../widgets/server_tile.dart';
import '../../home/home_screen.dart';
import '../../servers/data/country_card.dart';
import '../../../l10n/country_names.dart';
import '../../servers/domain/server.dart';
import '../../servers/domain/server_display_name.dart';
import '../../servers/domain/server_catalog_controller.dart';
import '../../servers/domain/server_providers.dart';
import '../../session/domain/session_controller.dart';
import '../../session/domain/session_state.dart';
import '../../session/domain/session_status.dart';
import '../../settings/domain/preferences_controller.dart';
import '../../settings/domain/preferences_state.dart';
import '../../settings/presentation/privacy_policy_consent_page.dart';
import '../../speedtest/presentation/widgets/speed_gauge.dart';
import 'onboarding_controller.dart';
import 'onboarding_speedtest_controller.dart';

class OnboardingFlow extends ConsumerStatefulWidget {
  const OnboardingFlow({super.key});

  @override
  ConsumerState<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends ConsumerState<OnboardingFlow> {
  late final PageController _pageController;
  int _currentPage = 0;
  bool _pendingConnect = false;
  bool _loggedStep3 = false;
  late final ProviderSubscription<ServerCatalogState>
      _serverCatalogSubscription;
  late final ProviderSubscription<SessionState> _sessionSubscription;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(ref
          .read(analyticsServiceProvider)
          .logEvent('onboarding_viewed_step_1'));
    });
    _serverCatalogSubscription = ref.listenManual<ServerCatalogState>(
      serverCatalogProvider,
      (previous, next) {
        ref.read(onboardingControllerProvider.notifier).maybeAssignAuto(next);
      },
    );
    _sessionSubscription = ref.listenManual<SessionState>(
      sessionControllerProvider,
      (previous, next) {
        _handleSessionState(previous, next);
      },
    );
  }

  @override
  void dispose() {
    _serverCatalogSubscription.close();
    _sessionSubscription.close();
    _pageController.dispose();
    super.dispose();
  }

  void _handleSessionState(SessionState? previous, SessionState next) {
    if (!_pendingConnect) {
      return;
    }
    if (previous?.status != SessionStatus.connected &&
        next.status == SessionStatus.connected) {
      _pendingConnect = false;
      ref.read(onboardingControllerProvider.notifier).setConnecting(false);
      unawaited(ref.read(analyticsServiceProvider).logEvent('connect_success'));
      unawaited(
        ref
            .read(preferencesControllerProvider.notifier)
            .setOnboardingCompleted(true),
      );
      unawaited(_navigateToHome());
    } else if (previous?.status != SessionStatus.error &&
        next.status == SessionStatus.error) {
      _pendingConnect = false;
      ref.read(onboardingControllerProvider.notifier).setConnecting(false);
      final message =
          next.errorMessage ?? 'Unable to establish VPN connection.';
      ref
          .read(onboardingControllerProvider.notifier)
          .setConnectionError(message);
      unawaited(ref.read(analyticsServiceProvider).logEvent(
        'connect_failure',
        {'message': message},
      ));
      unawaited(_showConnectionErrorSheet(message));
    } else if (next.status == SessionStatus.disconnected &&
        next.errorMessage != null &&
        (previous?.status == SessionStatus.preparing ||
            previous?.status == SessionStatus.connecting)) {
      _pendingConnect = false;
      ref.read(onboardingControllerProvider.notifier).setConnecting(false);
      final message = next.errorMessage!;
      ref
          .read(onboardingControllerProvider.notifier)
          .setConnectionError(message);
      unawaited(ref.read(analyticsServiceProvider).logEvent(
        'connect_failure',
        {'message': message, 'stage': 'disconnected'},
      ));
      unawaited(_showConnectionErrorSheet(message));
    }
  }

  Future<void> _goToPage(int index) async {
    setState(() {
      _currentPage = index;
    });
    await _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
    if (index == 2 && !_loggedStep3) {
      _loggedStep3 = true;
      unawaited(ref
          .read(analyticsServiceProvider)
          .logEvent('onboarding_step_3_viewed'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final onboardingState = ref.watch(onboardingControllerProvider);
    final speedTestState = ref.watch(onboardingSpeedTestControllerProvider);
    final preferences = ref.watch(preferencesControllerProvider);
    final size = MediaQuery.sizeOf(context);

    return WillPopScope(
      onWillPop: () async => true,
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: SafeArea(
          child: Stack(
            children: [
              PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                  });
                  if (index == 2 && !_loggedStep3) {
                    _loggedStep3 = true;
                    unawaited(ref
                        .read(analyticsServiceProvider)
                        .logEvent('onboarding_step_3_viewed'));
                  }
                },
                children: [
                  _WelcomePage(
                    onGetStarted: () {
                      unawaited(
                        ref
                            .read(analyticsServiceProvider)
                            .logEvent('onboarding_cta_step_1'),
                      );
                      _goToPage(1);
                    },
                    onLearnMore: _showHowItWorksSheet,
                    onPrivacyPolicy: _showPrivacyPolicy,
                  ),
                  _SpeedTestPage(
                    state: speedTestState,
                    onToggleOptIn: (value) {
                      ref
                          .read(onboardingSpeedTestControllerProvider.notifier)
                          .toggleOptIn(value);
                    },
                    onRunTest: () {
                      ref
                          .read(onboardingSpeedTestControllerProvider.notifier)
                          .startTest();
                    },
                    onCancelTest: () {
                      ref
                          .read(onboardingSpeedTestControllerProvider.notifier)
                          .cancelTest();
                    },
                    onContinue: () async {
                      if (!speedTestState.optIn) {
                        await ref.read(analyticsServiceProvider).logEvent(
                            'speedtest_skipped',
                            {'method': 'toggle_off_continue'});
                      }
                      _goToPage(2);
                    },
                    onSkip: () async {
                      await ref.read(analyticsServiceProvider).logEvent(
                          'speedtest_skipped', {'method': 'skip_button'});
                      _goToPage(2);
                    },
                    onLearnMore: _showSpeedTestLearnMoreSheet,
                    onDismissBanner: () {
                      ref
                          .read(onboardingSpeedTestControllerProvider.notifier)
                          .markBannerDismissed();
                    },
                  ),
                  _ConnectPage(
                    state: onboardingState,
                    preferences: preferences,
                    onSelectAuto: () async {
                      await ref
                          .read(onboardingControllerProvider.notifier)
                          .useAutoServer();
                    },
                    onSelectManual: () async {
                      final server = await _showServerPicker(context);
                      if (server != null) {
                        await ref
                            .read(onboardingControllerProvider.notifier)
                            .selectManualServer(server);
                      }
                    },
                    onImport: () async {
                      final config = await _pickOvpnConfig();
                      if (config != null) {
                        await ref
                            .read(onboardingControllerProvider.notifier)
                            .setImportedConfig(config);
                      }
                    },
                    onClearImport: () {
                      ref
                          .read(onboardingControllerProvider.notifier)
                          .clearImportedConfig();
                    },
                    onToggleAutoReconnect: (value) {
                      unawaited(ref
                          .read(preferencesControllerProvider.notifier)
                          .setAutoReconnect(value));
                    },
                    onOpenAlwaysOnSettings: _openAlwaysOnSettings,
                    onEnableNotifications: () => _requestNotifications(),
                    onAllowConnect: () {
                      _handleConnect(requestNotifications: true);
                    },
                    onConnectWithoutNotifications: () {
                      _handleConnect(requestNotifications: false);
                    },
                    onSkipSetup: () async {
                      await ref
                          .read(preferencesControllerProvider.notifier)
                          .setOnboardingCompleted(true);
                      await _navigateToHome();
                    },
                    onShowRisks: _showRisksSheet,
                    onCancelConnect: _handleCancelConnect,
                  ),
                ],
              ),
              if (_currentPage < 2)
                Positioned(
                  top: 0,
                  right: size.width > 400 ? 16 : 8,
                  child: TextButton(
                    onPressed: () {
                      _goToPage(2);
                    },
                    child: Text(context.l10n.tutorialSkip),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _navigateToHome() async {
    if (!mounted) return;
    await Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (route) => false,
    );
  }

  Future<void> _handleConnect({required bool requestNotifications}) async {
    final onboardingNotifier = ref.read(onboardingControllerProvider.notifier);
    final onboardingState = ref.read(onboardingControllerProvider);
    final analytics = ref.read(analyticsServiceProvider);

    final server = onboardingState.serverMode == OnboardingServerMode.imported
        ? onboardingState.importedConfig?.toServer()
        : onboardingState.selectedServer;

    if (server == null) {
      _showSnackBar(context.l10n.onboardingChooseServerFirst);
      return;
    }

    unawaited(analytics.logEvent('connect_tapped', {
      'notifications': requestNotifications,
      'selection': onboardingState.serverMode.name,
    }));

    onboardingNotifier.setConnecting(true);
    setState(() {
      _pendingConnect = true;
    });

    if (requestNotifications) {
      await _requestNotifications();
    }

    try {
      await ref.read(sessionControllerProvider.notifier).connect(
            context: context,
            server: server,
          );
    } catch (error) {
      onboardingNotifier.setConnecting(false);
      setState(() {
        _pendingConnect = false;
      });
      final message = error.toString();
      onboardingNotifier.setConnectionError(message);
      await analytics.logEvent('connect_failure', {'message': message});
      unawaited(_showConnectionErrorSheet(message));
    }
  }

  Future<void> _handleCancelConnect() async {
    final onboardingNotifier = ref.read(onboardingControllerProvider.notifier);
    final analytics = ref.read(analyticsServiceProvider);
    if (_pendingConnect || onboardingNotifier.state.connecting) {
      setState(() {
        _pendingConnect = false;
      });
      onboardingNotifier.setConnecting(false);
    }
    try {
      await ref.read(sessionControllerProvider.notifier).disconnect();
      unawaited(analytics.logEvent('connect_cancelled'));
      _showSnackBar(context.l10n.onboardingConnectionCancelled);
    } catch (error) {
      _showSnackBar(context.l10n.onboardingUnableCancelConnection('$error'));
    }
  }

  Future<bool> _requestNotifications() async {
    final notificationService = ref.read(sessionNotificationServiceProvider);
    try {
      final granted = await notificationService.requestPermission();
      final controller = ref.read(onboardingControllerProvider.notifier);
      controller.setNotificationsPrompted(true);
      controller.setNotificationsGranted(granted);
      controller.setShowNotificationDenied(!granted);
      if (!granted) {
        _showSnackBar(context.l10n.onboardingNotificationsOptional);
      }
      return granted;
    } on PlatformException catch (error) {
      final controller = ref.read(onboardingControllerProvider.notifier);
      controller.setNotificationsPrompted(true);
      controller.setNotificationsGranted(false);
      controller.setShowNotificationDenied(true);
      _showSnackBar(context.l10n
          .onboardingUnableRequestNotifications('${error.message}'));
      return false;
    }
  }

  Future<void> _showHowItWorksSheet() {
    return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        final l10n = context.l10n;
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.onboardingHowItWorksTitle,
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              _DiagramStep(
                icon: Icons.public,
                title: l10n.onboardingSlideServersTitle,
                description: l10n.onboardingHowItWorksServersDesc,
              ),
              _DiagramStep(
                icon: Icons.vpn_lock,
                title: l10n.onboardingSlideTunnelTitle,
                description: l10n.onboardingHowItWorksTunnelDesc,
              ),
              _DiagramStep(
                icon: Icons.account_circle_outlined,
                title: l10n.onboardingSlideAccountTitle,
                description: l10n.onboardingHowItWorksAccountDesc,
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showSpeedTestLearnMoreSheet() {
    return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        final l10n = context.l10n;
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.onboardingAboutSpeedTestTitle,
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              _BulletLine(l10n.onboardingAboutSpeedTestBullet1),
              _BulletLine(l10n.onboardingAboutSpeedTestBullet2),
              _BulletLine(l10n.onboardingAboutSpeedTestBullet3),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showRisksSheet() {
    return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) {
        final l10n = context.l10n;
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.onboardingRisksTitle,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              _BulletLine(l10n.onboardingRisksBullet1),
              _BulletLine(l10n.onboardingRisksBullet2),
              _BulletLine(l10n.onboardingRisksBullet3),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showConnectionErrorSheet(String message) {
    return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        final l10n = context.l10n;
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.onboardingConnectionFailed,
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                message,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      child: Text(l10n.onboardingTryAgain),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      child: Text(l10n.close),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showPrivacyPolicy() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const PrivacyPolicyConsentPage(),
        fullscreenDialog: true,
      ),
    );
  }

  Future<void> _openAlwaysOnSettings() async {
    if (!isAndroidNative) {
      _showSnackBar(context.l10n.onboardingAlwaysOnVpnAndroidOnly);
      return;
    }
    try {
      await AppSettings.openAppSettings(type: AppSettingsType.vpn);
    } catch (error) {
      _showSnackBar(context.l10n.onboardingUnableOpenVpnSettings('$error'));
    }
  }

  Future<Server?> _showServerPicker(BuildContext context) async {
    return showModalBottomSheet<Server>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return const SizedBox(
          height: 520,
          child: _OnboardingServerPickerSheet(),
        );
      },
    );
  }

  Future<ImportedOvpnConfig?> _pickOvpnConfig() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['ovpn'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) {
        return null;
      }
      final file = result.files.first;
      var data = file.bytes;
      if (data == null) {
        final path = file.path;
        if (path == null) {
          _showSnackBar(context.l10n.onboardingUnableReadFile);
          return null;
        }
        data = await File(path).readAsBytes();
      }
      final bytes = data;
      final content = utf8.decode(bytes);
      return _parseOvpn(content, file.name);
    } catch (error) {
      _showSnackBar(context.l10n.onboardingUnableImportConfig('$error'));
      return null;
    }
  }

  ImportedOvpnConfig? _parseOvpn(String content, String filename) {
    final lines =
        LineSplitter.split(content).map((line) => line.trim()).toList();
    final remoteLine = lines.firstWhere(
      (line) => line.startsWith('remote '),
      orElse: () => '',
    );
    if (remoteLine.isEmpty) {
      _showSnackBar(context.l10n.onboardingOvpnMissingRemote);
      return null;
    }
    final parts = remoteLine.split(RegExp(r'\s+'));
    if (parts.length < 3) {
      _showSnackBar(context.l10n.onboardingRemoteMustIncludeHostPort);
      return null;
    }
    final host = parts[1];
    final port = parts[2];
    final cipherLine = lines.firstWhere(
      (line) => line.startsWith('cipher '),
      orElse: () => '',
    );
    final cipher = cipherLine.isNotEmpty
        ? cipherLine.split(RegExp(r'\s+')).skip(1).join(' ')
        : null;
    final name = filename.replaceAll('.ovpn', '').trim().isEmpty
        ? context.l10n.onboardingImportedServer
        : filename.replaceAll('.ovpn', '').trim();
    return ImportedOvpnConfig(
      name: name,
      remote: '$host:$port',
      rawConfig: content,
      cipher: cipher,
    );
  }

  Future<void> _openLink(Uri uri) async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _showSnackBar(context.l10n.onboardingUnableOpenUrl(uri.toString()));
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class _OnboardingServerPickerSheet extends ConsumerStatefulWidget {
  const _OnboardingServerPickerSheet();

  @override
  ConsumerState<_OnboardingServerPickerSheet> createState() =>
      _OnboardingServerPickerSheetState();
}

class _OnboardingServerPickerSheetState
    extends ConsumerState<_OnboardingServerPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matches(dynamic cardOrServer) {
    if (_query.isEmpty) return true;
    final needle = _query.toLowerCase();
    if (cardOrServer is CountryCard) {
      final c = cardOrServer;
      if (countryMatchesSearch(needle, c.countryCode)) return true;
      final fields = <String?>[
        c.server?.name,
        c.server?.hostName,
      ];
      return fields
          .whereType<String>()
          .any((v) => v.toLowerCase().contains(needle));
    }
    final s = cardOrServer as Server;
    final fields = <String?>[
      s.name,
      s.countryName,
      s.countryCode,
      s.cityName,
      s.regionName,
      s.hostName,
    ];
    return fields
        .whereType<String>()
        .any((v) => v.toLowerCase().contains(needle));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final catalog = ref.watch(serverCatalogProvider);
    final onboardingState = ref.watch(onboardingControllerProvider);
    final cards = catalog.sortedCountryCards
        .where((c) => c.server != null && _matches(c))
        .toList(growable: false);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Browse community list',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      catalog.countryCards.isEmpty
                          ? 'Fetching volunteer servers…'
                          : '${cards.length} of ${catalog.countryCards.length} locations shown',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.65),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: context.l10n.commonRefresh,
                onPressed: () async {
                  await ref
                      .read(serverCatalogProvider.notifier)
                      .refreshServers();
                },
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: TextField(
            controller: _searchController,
            onChanged: (value) {
              setState(() {
                _query = value.trim();
              });
            },
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              labelText: context.l10n.commonSearchLocations,
              suffixIcon: _query.isNotEmpty
                  ? IconButton(
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _query = '';
                        });
                      },
                      icon: const Icon(Icons.clear),
                    )
                  : null,
              border: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(16)),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Builder(
            builder: (context) {
              if (catalog.isLoading) {
                return const Center(child: CircularProgressIndicator());
              }
              if (catalog.error != null && catalog.countryCards.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    'Unable to load servers: ${catalog.error}',
                    textAlign: TextAlign.center,
                  ),
                );
              }
              if (cards.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    _query.isEmpty
                        ? 'No community servers are available right now. Pull to refresh later.'
                        : 'No locations match "${_searchController.text}".',
                    textAlign: TextAlign.center,
                  ),
                );
              }
              return RefreshIndicator(
                onRefresh: () async {
                  await ref
                      .read(serverCatalogProvider.notifier)
                      .refreshServers();
                },
                child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: cards.length,
                  itemBuilder: (context, index) {
                    final card = cards[index];
                    final server = card.server!;
                    final selectedId = onboardingState.selectedServer?.id;
                    return ServerTile(
                      server: server,
                      selected: selectedId == server.id,
                      latencyMs: card.latencyMs,
                      onTap: () {
                        Navigator.of(context).pop(server);
                      },
                    );
                  },
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _WelcomePage extends StatelessWidget {
  const _WelcomePage({
    required this.onGetStarted,
    required this.onLearnMore,
    required this.onPrivacyPolicy,
  });

  final VoidCallback onGetStarted;
  final VoidCallback onLearnMore;
  final VoidCallback onPrivacyPolicy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: SvgPicture.asset(
                  'assets/s1.svg',
                  height: constraints.maxHeight > 600 ? 240 : 200,
                ),
              ),
              const SizedBox(height: 32),
              Text(
                l10n.onboardingIntroTitle,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              _BulletLine(l10n.onboardingIntroBullet1),
              _BulletLine(l10n.onboardingIntroBullet2),
              _BulletLine(l10n.onboardingIntroBullet3),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: onGetStarted,
                child: Text(l10n.onboardingGetStarted),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: onLearnMore,
                child: Text(l10n.onboardingLearnHowItWorks),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  TextButton(
                    onPressed: onPrivacyPolicy,
                    child: Text(l10n.onboardingPrivacyPolicy),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SpeedTestPage extends StatelessWidget {
  const _SpeedTestPage({
    required this.state,
    required this.onToggleOptIn,
    required this.onRunTest,
    required this.onCancelTest,
    required this.onContinue,
    required this.onSkip,
    required this.onLearnMore,
    required this.onDismissBanner,
  });

  final OnboardingSpeedTestState state;
  final ValueChanged<bool> onToggleOptIn;
  final VoidCallback onRunTest;
  final VoidCallback onCancelTest;
  final VoidCallback onContinue;
  final VoidCallback onSkip;
  final VoidCallback onLearnMore;
  final VoidCallback onDismissBanner;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: SvgPicture.asset(
              'assets/s2.svg',
              height: 220,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            l10n.onboardingSpeedTestTitle,
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.onboardingSpeedTestBody,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.onboardingSpeedTestDisclaimer,
                    style: theme.textTheme.bodyMedium,
                  ),
                  TextButton(
                    onPressed: onLearnMore,
                    child: Text(l10n.onboardingLearnMore),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          SwitchListTile.adaptive(
            value: state.optIn,
            onChanged: onToggleOptIn,
            title: Text(l10n.onboardingSpeedTestOptIn),
          ),
          if (state.showUnavailableBanner)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: MaterialBanner(
                content: Text(l10n.onboardingSpeedTestUnavailable),
                actions: [
                  TextButton(
                      onPressed: onDismissBanner,
                      child: Text(l10n.onboardingDismiss)),
                ],
              ),
            ),
          if (state.optIn) ...[
            const SizedBox(height: 16),
            _SpeedProgress(state: state),
          ],
          const SizedBox(height: 24),
          if (state.optIn && state.status == OnboardingSpeedTestStatus.running)
            FilledButton(
              onPressed: onCancelTest,
              child: Text(l10n.onboardingCancelTest),
            )
          else
            FilledButton(
              onPressed: state.optIn
                  ? (state.status == OnboardingSpeedTestStatus.completed
                      ? onContinue
                      : onRunTest)
                  : onContinue,
              child: Text(state.optIn
                  ? (state.status == OnboardingSpeedTestStatus.completed
                      ? l10n.onboardingContinue
                      : l10n.onboardingRunQuickTest)
                  : l10n.onboardingContinue),
            ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: onSkip,
            child: Text(l10n.tutorialSkip),
          ),
        ],
      ),
    );
  }
}

class _ConnectPage extends StatelessWidget {
  const _ConnectPage({
    required this.state,
    required this.preferences,
    required this.onSelectAuto,
    required this.onSelectManual,
    required this.onImport,
    required this.onClearImport,
    required this.onToggleAutoReconnect,
    required this.onOpenAlwaysOnSettings,
    required this.onEnableNotifications,
    required this.onAllowConnect,
    required this.onConnectWithoutNotifications,
    required this.onSkipSetup,
    required this.onShowRisks,
    required this.onCancelConnect,
  });

  final OnboardingState state;
  final PreferencesState preferences;
  final Future<void> Function() onSelectAuto;
  final Future<void> Function() onSelectManual;
  final Future<void> Function() onImport;
  final VoidCallback onClearImport;
  final ValueChanged<bool> onToggleAutoReconnect;
  final Future<void> Function() onOpenAlwaysOnSettings;
  final Future<bool> Function() onEnableNotifications;
  final VoidCallback onAllowConnect;
  final VoidCallback onConnectWithoutNotifications;
  final Future<void> Function() onSkipSetup;
  final Future<void> Function() onShowRisks;
  final Future<void> Function() onCancelConnect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final baseline = state.speedTestSummary;
    final isConnecting = state.connecting;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: SvgPicture.asset(
              'assets/s3.svg',
              height: 220,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            l10n.onboardingConnectTitle,
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (baseline != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Chip(
                avatar: const Icon(Icons.speed, size: 18),
                label: Text(
                  l10n.onboardingBaseline(
                    baseline.downloadMbps.toStringAsFixed(0),
                    baseline.uploadMbps.toStringAsFixed(0),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 16),
          _SectionHeader(title: l10n.onboardingSectionServer),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: Text(l10n.onboardingBestServerAuto),
                selected: state.serverMode == OnboardingServerMode.auto,
                onSelected: (_) => unawaited(onSelectAuto()),
              ),
              ChoiceChip(
                label: Text(l10n.onboardingBrowseCommunityList),
                selected: state.serverMode == OnboardingServerMode.manual,
                onSelected: (_) => unawaited(onSelectManual()),
              ),
              ChoiceChip(
                label: Text(l10n.onboardingImportOvpn),
                selected: state.serverMode == OnboardingServerMode.imported,
                onSelected: (_) => unawaited(onImport()),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (state.serverMode != OnboardingServerMode.imported &&
              state.selectedServer != null)
            _ServerSummaryCard(server: state.selectedServer!),
          if (state.serverMode == OnboardingServerMode.imported &&
              state.importedConfig != null)
            _ImportedConfigCard(
                config: state.importedConfig!, onClear: onClearImport),
          const SizedBox(height: 24),
          _SectionHeader(title: l10n.onboardingSectionOptions),
          const SizedBox(height: 8),
          SwitchListTile.adaptive(
            value: preferences.autoReconnect,
            onChanged: onToggleAutoReconnect,
            title: Text(l10n.onboardingAutoReconnect),
          ),
          ListTile(
            title: Text(l10n.onboardingAlwaysOnVpn),
            subtitle: Text(l10n.onboardingAlwaysOnVpnSubtitle),
            onTap: () {
              unawaited(onOpenAlwaysOnSettings());
            },
            trailing: const Icon(Icons.open_in_new),
          ),
          const SizedBox(height: 16),
          _SectionHeader(title: l10n.onboardingSectionPermissions),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.vpn_lock),
            title: Text(l10n.onboardingVpnPermission),
            subtitle: Text(l10n.onboardingVpnPermissionSubtitle),
          ),
          ListTile(
            leading: Icon(
              state.notificationsGranted
                  ? Icons.notifications_active
                  : Icons.notifications_none,
            ),
            title: Text(l10n.onboardingNotificationsTitle),
            subtitle: Text(state.notificationsPrompted
                ? (state.notificationsGranted
                    ? l10n.onboardingNotificationsEnabledSubtitle
                    : l10n.onboardingNotificationsDeniedSubtitle)
                : l10n.onboardingNotificationsRecommendedSubtitle),
            trailing: TextButton(
              onPressed: () {
                unawaited(onEnableNotifications());
              },
              child: Text(l10n.onboardingEnable),
            ),
          ),
          if (state.showNotificationDenied)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                l10n.onboardingNotificationsDisabledForNow,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: isConnecting ? null : onAllowConnect,
            child: isConnecting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l10n.onboardingAllowAndConnect),
          ),
          const SizedBox(height: 12),
          if (isConnecting)
            OutlinedButton.icon(
              onPressed: () {
                unawaited(onCancelConnect());
              },
              icon: const Icon(Icons.close),
              label: Text(l10n.onboardingCancelConnection),
            )
          else
            OutlinedButton(
              onPressed: onConnectWithoutNotifications,
              child: Text(l10n.onboardingConnectWithoutNotifications),
            ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () {
              if (isConnecting) {
                unawaited(onCancelConnect());
              }
              unawaited(onSkipSetup());
            },
            child: Text(l10n.onboardingSetupLater),
          ),
          const SizedBox(height: 24),
          Text(
            l10n.onboardingVpnGateDisclaimer,
            style: theme.textTheme.bodySmall,
          ),
          TextButton(
            onPressed: () {
              unawaited(onShowRisks());
            },
            child: Text(l10n.onboardingKnowTheRisks),
          ),
        ],
      ),
    );
  }
}

class _SpeedProgress extends StatelessWidget {
  const _SpeedProgress({required this.state});

  final OnboardingSpeedTestState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final gaugeStatus = () {
      switch (state.status) {
        case OnboardingSpeedTestStatus.running:
          return l10n.onboardingSpeedTestTesting;
        case OnboardingSpeedTestStatus.completed:
          return l10n.onboardingSpeedTestResultReady;
        case OnboardingSpeedTestStatus.error:
          return l10n.onboardingSpeedTestUnavailableShort;
        case OnboardingSpeedTestStatus.idle:
        default:
          return state.optIn
              ? l10n.onboardingSpeedTestReady
              : l10n.onboardingSpeedTestSkipped;
      }
    }();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: SpeedGauge(
                needleValue: state.downloadMbps.clamp(0, 100),
                displayValue: state.downloadMbps,
                maxValue: 100,
                statusLabel: gaugeStatus,
              ),
            ),
            const SizedBox(height: 16),
            if (state.isRunning) ...[
              LinearProgressIndicator(
                  value: state.progress > 0 ? state.progress : null),
              const SizedBox(height: 8),
              Text(
                l10n.onboardingSpeedTestCollecting,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.7),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
            ],
            Row(
              children: [
                Expanded(
                  child: _MetricTile(
                    label: l10n.onboardingLabelDownload,
                    value: state.downloadMbps > 0
                        ? '${state.downloadMbps.toStringAsFixed(1)} Mbps'
                        : state.isRunning
                            ? l10n.onboardingSpeedTestMeasuring
                            : '--',
                    icon: Icons.download,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _MetricTile(
                    label: l10n.onboardingLabelUpload,
                    value: state.uploadMbps > 0
                        ? '${state.uploadMbps.toStringAsFixed(1)} Mbps'
                        : state.isRunning
                            ? l10n.onboardingSpeedTestPending
                            : '--',
                    icon: Icons.upload,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _MetricTile(
              label: l10n.onboardingLabelLatency,
              value: state.latency != null
                  ? '${state.latency!.inMilliseconds} ms'
                  : state.isRunning
                      ? l10n.onboardingSpeedTestChecking
                      : '--',
              icon: Icons.podcasts,
            ),
            if (state.errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  state.errorMessage!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile(
      {required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.7))),
              Text(value,
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      title,
      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
    );
  }
}

class _ServerSummaryCard extends StatelessWidget {
  const _ServerSummaryCard({required this.server});

  final Server server;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              localizedServerDisplayName(server, l10n),
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text(
              localizedServerLocation(server, l10n),
              style: theme.textTheme.bodySmall,
            ),
            if (server.downloadSpeed != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  l10n.onboardingRecentThroughput(
                    (server.downloadSpeed! / 1000).toStringAsFixed(1),
                  ),
                ),
              ),
            if (server.sessions != null)
              Text(l10n.onboardingActiveSessions(server.sessions!)),
          ],
        ),
      ),
    );
  }
}

class _ImportedConfigCard extends StatelessWidget {
  const _ImportedConfigCard({required this.config, required this.onClear});

  final ImportedOvpnConfig config;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    config.name,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  onPressed: onClear,
                  icon: const Icon(Icons.close),
                  tooltip: context.l10n.commonRemove,
                ),
              ],
            ),
            Text(context.l10n.onboardingRemoteLabel(config.remote)),
            if (config.cipher != null)
              Text(context.l10n.onboardingCipherLabel(config.cipher!)),
          ],
        ),
      ),
    );
  }
}

class _BulletLine extends StatelessWidget {
  const _BulletLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• '),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _DiagramStep extends StatelessWidget {
  const _DiagramStep(
      {required this.icon, required this.title, required this.description});

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(description, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
