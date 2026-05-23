import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/colors.dart';

enum GlassSurface {
  raised,
  nav,
  flat,
}

/// UIBlurEffect.systemMaterial — light tint, specular sheen, soft white rim.
class FrostedGlass extends StatelessWidget {
  const FrostedGlass({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.padding,
    this.margin,
    this.blurSigma,
    this.surface = GlassSurface.raised,
    this.boxShadow,
    this.enabled = true,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? blurSigma;
  final GlassSurface surface;
  final List<BoxShadow>? boxShadow;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final sigma = enabled
        ? (blurSigma ??
            (surface == GlassSurface.nav
                ? HiVpnGlass.blurSigmaNav
                : HiVpnGlass.blurSigma))
        : 0.0;
    final fill = surface == GlassSurface.nav ? HiVpnGlass.tintNav : HiVpnGlass.tint;
    final shadow = boxShadow ??
        (surface == GlassSurface.flat
            ? const <BoxShadow>[]
            : surface == GlassSurface.nav
                ? HiVpnGlass.shadowNav
                : HiVpnGlass.shadow);

    Widget panel = RepaintBoundary(
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: borderRadius,
                    color: fill,
                    border: Border.all(
                      color: HiVpnGlass.borderLight,
                      width: 0.6,
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: borderRadius,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: 0.22),
                        Colors.white.withValues(alpha: 0.04),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.18, 0.45],
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: CustomPaint(
                  painter: _GlassRimPainter(borderRadius: borderRadius),
                ),
              ),
              Padding(
                padding: padding ?? EdgeInsets.zero,
                child: child,
              ),
            ],
          ),
        ),
      ),
    );

    if (shadow.isNotEmpty) {
      panel = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: shadow,
        ),
        child: panel,
      );
    }

    if (margin != null) {
      panel = Padding(padding: margin!, child: panel);
    }

    return panel;
  }
}

class _GlassRimPainter extends CustomPainter {
  _GlassRimPainter({required this.borderRadius});

  final BorderRadius borderRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = borderRadius.toRRect(rect);

    final highlightHeight = (size.height * 0.1).clamp(4.0, 32.0);
    final topHighlight = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          HiVpnGlass.innerHighlight,
          HiVpnGlass.innerHighlight.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, highlightHeight));

    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(0.5, 0.5, size.width - 1, highlightHeight),
        topLeft: borderRadius.topLeft,
        topRight: borderRadius.topRight,
      ),
      topHighlight,
    );

    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..color = Colors.white.withValues(alpha: 0.65);

    canvas.drawRRect(rrect.deflate(0.5), rim);
  }

  @override
  bool shouldRepaint(covariant _GlassRimPainter oldDelegate) => false;
}

class HiVpnGlassBackground extends StatelessWidget {
  const HiVpnGlassBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: HiVpnGlass.baseCanvas,
      child: child,
    );
  }
}

class HiVpnSheetScaffold extends StatelessWidget {
  const HiVpnSheetScaffold({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: HiVpnGlass.sheetBackground,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: child,
      ),
    );
  }
}
