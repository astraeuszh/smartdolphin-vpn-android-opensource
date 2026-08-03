import 'package:flutter/material.dart';

import 'colors.dart';

/// Platform system typography — SF Pro on Apple, Roboto/system on Android (no bundled web fonts).
ThemeData buildHiVpnTheme({
  String accentSeed = 'ocean',
  Brightness brightness = Brightness.light,
}) {
  final accent = _accentFromSeed(accentSeed);
  final dark = brightness == Brightness.dark;
  final colorScheme = ColorScheme(
    brightness: brightness,
    primary: accent,
    onPrimary: HiVpnColors.onPrimary,
    primaryContainer: dark ? const Color(0xFF17365F) : const Color(0x14000000),
    onPrimaryContainer: dark ? Colors.white : HiVpnColors.lightOnSurface,
    secondary:
        dark ? const Color(0xFFC4C8CE) : HiVpnColors.lightOnSurfaceVariant,
    onSecondary: HiVpnColors.onPrimary,
    secondaryContainer:
        dark ? const Color(0xFF20242A) : const Color(0x0F000000),
    onSecondaryContainer:
        dark ? Colors.white70 : HiVpnColors.lightOnSurfaceVariant,
    tertiary: HiVpnColors.mutedGray,
    onTertiary: HiVpnColors.onPrimary,
    error: HiVpnColors.error,
    onError: HiVpnColors.onPrimary,
    errorContainer: const Color(0xCCFEE2E2),
    onErrorContainer: const Color(0xFF991B1B),
    surface: dark ? const Color(0xFF202428) : HiVpnColors.lightSurface,
    onSurface: dark ? const Color(0xFFF4F5F7) : HiVpnColors.lightOnSurface,
    surfaceContainerHighest:
        dark ? const Color(0xFF30353A) : HiVpnColors.lightSurfaceVariant,
    onSurfaceVariant:
        dark ? const Color(0xFFBCC1C7) : HiVpnColors.lightOnSurfaceVariant,
    outline: HiVpnColors.mutedGray.withValues(alpha: 0.55),
    outlineVariant: HiVpnColors.mutedGray.withValues(alpha: 0.35),
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: const Color(0xFF1F2937),
    onInverseSurface: const Color(0xFFF9FAFB),
    inversePrimary: const Color(0xFF93C5FD),
    surfaceTint: Colors.transparent,
  );

  final textTheme =
      (dark ? ThemeData.dark() : ThemeData.light()).textTheme.apply(
            bodyColor: colorScheme.onSurface,
            displayColor: colorScheme.onSurface,
          );

  return ThemeData(
    colorScheme: colorScheme,
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: Colors.transparent,
    dividerColor: colorScheme.outline.withValues(alpha: 0.45),
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: colorScheme.onSurface,
      elevation: 0,
      centerTitle: false,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: const Color(0xE6111827),
      contentTextStyle: const TextStyle(color: Colors.white),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: dark ? const Color(0xFF2B3035) : HiVpnGlass.fillStrong,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        color: colorScheme.onSurface,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      contentTextStyle: TextStyle(
        color: colorScheme.onSurfaceVariant,
        fontSize: 14,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        foregroundColor: colorScheme.onPrimary,
        backgroundColor: colorScheme.primary,
        elevation: 0,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        side: BorderSide(color: HiVpnColors.mutedGray.withValues(alpha: 0.65)),
        foregroundColor: colorScheme.onSurface,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    cardTheme: CardThemeData(
      color: dark ? const Color(0xD12E3338) : HiVpnGlass.fillStrong,
      elevation: 0,
      shadowColor: const Color(0xFF64748B).withValues(alpha: 0.16),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: dark
              ? Colors.white.withValues(alpha: 0.10)
              : Colors.white.withValues(alpha: 0.88),
        ),
      ),
      margin: EdgeInsets.zero,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.transparent,
      indicatorColor: colorScheme.primaryContainer.withValues(alpha: 0.85),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      height: 64,
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return IconThemeData(color: colorScheme.primary, size: 26);
        }
        return IconThemeData(
          color: colorScheme.onSurfaceVariant,
          size: 26,
        );
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return TextStyle(
            color: colorScheme.primary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          );
        }
        return TextStyle(
          color: colorScheme.onSurfaceVariant,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        );
      }),
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: Colors.transparent,
      selectedItemColor: colorScheme.primary,
      unselectedItemColor: colorScheme.onSurfaceVariant,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark
          ? Colors.white.withValues(alpha: 0.06)
          : Colors.white.withValues(alpha: 0.68),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: Colors.white.withValues(alpha: dark ? 0.12 : 0.9),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: Colors.white.withValues(alpha: dark ? 0.12 : 0.9),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
      ),
      labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
      hintStyle:
          TextStyle(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8)),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return colorScheme.primary;
        return dark ? const Color(0xFF30353A) : Colors.white;
      }),
      checkColor: WidgetStatePropertyAll(colorScheme.onPrimary),
      side: BorderSide(color: colorScheme.outline, width: 1.2),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? colorScheme.primary
              : colorScheme.onSurfaceVariant),
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? colorScheme.primary.withValues(alpha: 0.72)
              : (dark ? const Color(0xFF3A3F44) : const Color(0xFFD7DCE2))),
      thumbColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? colorScheme.onPrimary
              : (dark ? const Color(0xFFB8C2CB) : Colors.white)),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xFF30353A) : Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      ),
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(
          dark ? const Color(0xFF292E33) : Colors.white,
        ),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: dark ? const Color(0xFF292E33) : Colors.white,
      surfaceTintColor: Colors.transparent,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: dark ? const Color(0xFF292E33) : const Color(0xFFF8FBFF),
      modalBackgroundColor:
          dark ? const Color(0xFF292E33) : const Color(0xFFF8FBFF),
      surfaceTintColor: Colors.transparent,
    ),
  );
}

extension HiVpnThemeX on ThemeData {
  Color get elevatedSurface => HiVpnGlass.fillStrong;

  Color pastelCard(Color accent, {double opacity = 0.14}) {
    return Color.alphaBlend(accent.withValues(alpha: opacity), HiVpnGlass.fill);
  }
}

Color _accentFromSeed(String seed) {
  switch (seed) {
    case 'aqua':
      return const Color(0xFF0891B2);
    case 'sunrise':
      return const Color(0xFFD97706);
    case 'forest':
      return const Color(0xFF16A34A);
    case 'lavender':
      return const Color(0xFF7C3AED);
    case 'ocean':
    default:
      return HiVpnColors.accent;
  }
}
