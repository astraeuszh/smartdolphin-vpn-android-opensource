import 'package:flutter/material.dart';

class HiVpnColors {
  static const Color lightBackground = Color(0xFFF5F5F7);
  static const Color lightSurface = Color(0xFFF2F2F7);
  static const Color lightSurfaceVariant = Color(0xFFE8E8ED);
  static const Color lightPrimary = Color(0xFF4A7FD4);
  static const Color lightPrimaryContainer = Color(0x554A7FD4);
  static const Color lightOnSurface = Color(0xFF3A4150);
  static const Color lightOnSurfaceVariant = Color(0xFF7B8494);
  static const Color mutedGray = Color(0xFFB8BEC8);

  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color accent = lightPrimary;
  static const Color success = Color(0xFF3FAE62);
  static const Color warning = Color(0xFFD49A2A);
  static const Color error = Color(0xFFD95555);
  static const Color info = Color(0xFF4A7FD4);

  static const Color primary = lightPrimary;
  static const Color primaryContainer = lightPrimaryContainer;
  static const Color background = lightBackground;
  static const Color surface = lightSurface;
  static const Color onSurface = lightOnSurface;
}

/// Recovered early glass tokens (transcript ~L1966): systemMaterial on F5F5F7 canvas.
class HiVpnGlass {
  static const double blurSigma = 20;
  static const double blurSigmaNav = 24;

  static const Color baseCanvas = Color(0xFFF5F5F7);

  static const Color tint = Color(0xA3FFFFFF);
  static const Color tintNav = Color(0xB8FFFFFF);
  static const Color tintSheet = Color(0xFFF8FBFF);
  static const Color sheetBackground = Color(0xFFF5F8FC);

  static const Color borderLight = Color(0xB3FFFFFF);
  static const Color innerHighlight = Color(0x99FFFFFF);

  static const Color fill = tint;
  static const Color fillSubtle = Color(0x80FFFFFF);
  static const Color fillStrong = Color(0xD9FFFFFF);

  // Legacy aliases used elsewhere in the app.
  static const Color panelFill = tint;
  static const Color insetFill = tint;
  static const Color insetFillNav = tintNav;
  static const Color rimPaleWhite = borderLight;
  static const Color rimSilver = borderLight;
  static const Color rimSilverLight = innerHighlight;
  static const double rimStrokeWidth = 0.6;
  static const double rimWidth = 0.6;

  static const List<BoxShadow> shadow = [
    BoxShadow(
      color: Color(0x0A000000),
      blurRadius: 28,
      offset: Offset(0, 6),
      spreadRadius: -4,
    ),
    BoxShadow(
      color: Color(0x06000000),
      blurRadius: 4,
      offset: Offset(0, 1),
    ),
  ];

  static const List<BoxShadow> shadowNav = [
    BoxShadow(
      color: Color(0x0C000000),
      blurRadius: 32,
      offset: Offset(0, 8),
      spreadRadius: -6,
    ),
    BoxShadow(
      color: Color(0x06000000),
      blurRadius: 6,
      offset: Offset(0, 2),
    ),
  ];

  static const List<BoxShadow> shadowFlat = [];
  static const List<BoxShadow> insetShadow = [];
}
