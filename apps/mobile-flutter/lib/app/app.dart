import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/startup/splash_check_screen.dart';
import '../features/smart_stable/smart_stable_lifecycle.dart';
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
        return HiVpnGlassBackground(
          child: SmartStableLifecycle(
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
      home: const SplashCheckScreen(),
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
  const names = {
    'en': 'English',
    'zh': '简体中文',
    'zh_Hant_TW': '繁體中文',
    'es': 'Español',
    'pt_BR': 'Português',
    'de': 'Deutsch',
    'fr': 'Français',
    'ja': '日本語',
    'ko': '한국어',
  };
  return names[tag] ?? tag;
}

class _AppError extends StatelessWidget {
  const _AppError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Failed to load preferences.\n$message',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
