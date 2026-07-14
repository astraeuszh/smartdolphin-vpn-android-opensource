import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/startup/splash_check_screen.dart';
import '../features/auth/domain/auth_controller.dart';
import '../features/smart_stable/smart_stable_lifecycle.dart';
import '../services/logging/vpn_logger.dart';
import '../features/settings/domain/preferences_controller.dart';
import '../features/settings/domain/settings_controller.dart';
import '../l10n/app_localizations.dart';
import '../theme/theme.dart';
import '../widgets/frosted_glass.dart';

final navigatorKeyProvider = Provider<GlobalKey<NavigatorState>>((ref) {
  return GlobalKey<NavigatorState>();
});

class SmartDolphinApp extends ConsumerWidget {
  const SmartDolphinApp({super.key});

  static const _defaultLocaleCode = 'en';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(preferencesReadyProvider);
    final preferences = ref.watch(preferencesControllerProvider);
    final accentSeed = ref.watch(settingsControllerProvider).accentSeed;
    final localeTag = preferences.localeCode ?? _defaultLocaleCode;

    return MaterialApp(
      onGenerateTitle: (context) => context.l10n.appTitle,
      theme: buildHiVpnTheme(accentSeed: accentSeed),
      themeMode: ThemeMode.light,
      debugShowCheckedModeBanner: false,
      themeAnimationDuration: Duration.zero,
      themeAnimationCurve: Curves.linear,
      locale: parseLocaleFromTag(localeTag),
      localeResolutionCallback: (deviceLocale, supportedLocales) {
        final preferred = parseLocaleFromTag(localeTag);
        for (final supported in supportedLocales) {
          if (supported.languageCode == preferred.languageCode &&
              supported.countryCode == preferred.countryCode &&
              supported.scriptCode == preferred.scriptCode) {
            return supported;
          }
        }
        for (final supported in supportedLocales) {
          if (supported.languageCode == preferred.languageCode) {
            return supported;
          }
        }
        return parseLocaleFromTag(_defaultLocaleCode);
      },
      navigatorKey: ref.watch(navigatorKeyProvider),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // SmartStableLifecycle must live BELOW MaterialApp: its banner Stack needs
      // Directionality/Theme/Localizations/MediaQuery from the app. Mounting it
      // above MaterialApp crashed every frame with "No Directionality widget found".
      builder: (context, child) {
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (event) {
            ref.read(vpnLoggerProvider).userAction(
                  'pointer',
                  'down',
                  'x=${event.position.dx.round()}, y=${event.position.dy.round()}',
                );
          },
          child: _ForegroundPresenceHeartbeat(
            child: _AppLifecycleGate(
              child: HiVpnGlassBackground(
                child: SmartStableLifecycle(
                  child: child ?? const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        );
      },
      home: const SplashCheckScreen(),
    );
  }
}

/// Keeps the admin presence indicator accurate while the app is visibly in
/// use. It is intentionally inactive in the background and uses a relaxed
/// cadence to avoid a persistent network or battery cost.
class _ForegroundPresenceHeartbeat extends ConsumerStatefulWidget {
  const _ForegroundPresenceHeartbeat({required this.child});

  final Widget child;

  @override
  ConsumerState<_ForegroundPresenceHeartbeat> createState() =>
      _ForegroundPresenceHeartbeatState();
}

class _ForegroundPresenceHeartbeatState
    extends ConsumerState<_ForegroundPresenceHeartbeat>
    with WidgetsBindingObserver {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      _start();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _start();
    } else {
      _timer?.cancel();
      _timer = null;
      unawaited(ref
          .read(authControllerProvider.notifier)
          .setForegroundPresence(false));
    }
  }

  void _start() {
    _timer?.cancel();
    unawaited(
        ref.read(authControllerProvider.notifier).setForegroundPresence(true));
    _timer = Timer.periodic(const Duration(seconds: 35), (_) {
      unawaited(ref
          .read(authControllerProvider.notifier)
          .setForegroundPresence(true));
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Stops all Flutter tickers while the app is not visible and explicitly
/// requests a fresh frame after Android recreates the rendering surface.
class _AppLifecycleGate extends StatefulWidget {
  const _AppLifecycleGate({required this.child});

  final Widget child;

  @override
  State<_AppLifecycleGate> createState() => _AppLifecycleGateState();
}

class _AppLifecycleGateState extends State<_AppLifecycleGate>
    with WidgetsBindingObserver {
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (_foreground != foreground && mounted) {
      setState(() => _foreground = foreground);
    }
    if (foreground) {
      WidgetsBinding.instance.scheduleWarmUpFrame();
      WidgetsBinding.instance.ensureVisualUpdate();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return TickerMode(
      enabled: _foreground,
      child: RepaintBoundary(child: widget.child),
    );
  }
}

Locale parseLocaleFromTag(String tag) {
  final parts = tag.split('_');
  if (parts.length == 3) {
    return Locale.fromSubtags(
      languageCode: parts[0],
      scriptCode: parts[1],
      countryCode: parts[2],
    );
  }
  if (parts.length == 2) {
    if (parts[1].length == 4) {
      return Locale.fromSubtags(languageCode: parts[0], scriptCode: parts[1]);
    }
    return Locale(parts[0], parts[1]);
  }
  return Locale(parts[0]);
}

String localeToTag(Locale locale) {
  final buf = StringBuffer(locale.languageCode);
  if (locale.scriptCode != null && locale.scriptCode!.isNotEmpty) {
    buf.write('_${locale.scriptCode}');
  }
  if (locale.countryCode != null && locale.countryCode!.isNotEmpty) {
    buf.write('_${locale.countryCode}');
  }
  return buf.toString();
}

String localeDisplayName(Locale locale) {
  final tag = localeToTag(locale);
  const names = <String, String>{
    'en': 'English',
    'zh': '\u7b80\u4f53\u4e2d\u6587',
    'zh_Hant_TW': '\u7e41\u9ad4\u4e2d\u6587',
    'es': 'Espa\u00f1ol',
    'ja': '\u65e5\u672c\u8a9e',
  };
  return names[tag] ?? tag;
}
