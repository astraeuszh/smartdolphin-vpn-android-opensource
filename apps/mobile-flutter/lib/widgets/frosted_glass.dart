import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/colors.dart';

enum GlassSurface {
  raised,
  nav,
  flat,
}

class LiquidGlass extends StatefulWidget {
  const LiquidGlass({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
    this.padding,
    this.margin,
    this.blurSigma = 16,
    this.liveBlur = false,
    this.enabled = true,
    this.onTap,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double blurSigma;
  final bool liveBlur;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  State<LiquidGlass> createState() => _LiquidGlassState();
}

class _LiquidGlassState extends State<LiquidGlass> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    Widget panel = AnimatedScale(
      scale: _pressed ? 0.985 : 1,
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: widget.borderRadius,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF64748B).withValues(alpha: 0.16),
              blurRadius: 34,
              offset: const Offset(0, 16),
              spreadRadius: -12,
            ),
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.72),
              blurRadius: 14,
              offset: const Offset(-5, -6),
              spreadRadius: -9,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: widget.borderRadius,
          child: Stack(
            children: [
              if (widget.enabled && widget.liveBlur && widget.blurSigma > 0)
                Positioned.fill(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: widget.blurSigma,
                      sigmaY: widget.blurSigma,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: widget.borderRadius,
                    color: Colors.white.withValues(alpha: 0.64),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.95),
                      width: 1,
                    ),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: 0.92),
                        const Color(0xFFF8FBFF).withValues(alpha: 0.66),
                        const Color(0xFFE9F1FA).withValues(alpha: 0.42),
                      ],
                      stops: const [0, 0.46, 1],
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: CustomPaint(
                  painter:
                      _LiquidGlassPainter(borderRadius: widget.borderRadius),
                ),
              ),
              Padding(
                padding: widget.padding ?? EdgeInsets.zero,
                child: widget.child,
              ),
            ],
          ),
        ),
      ),
    );

    if (widget.onTap != null) {
      panel = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _setPressed(true),
        onTapCancel: () => _setPressed(false),
        onTapUp: (_) => _setPressed(false),
        onTap: widget.onTap,
        child: panel,
      );
    }

    if (widget.margin != null) {
      panel = Padding(padding: widget.margin!, child: panel);
    }

    return panel;
  }
}

class _LiquidGlassPainter extends CustomPainter {
  const _LiquidGlassPainter({required this.borderRadius});

  final BorderRadius borderRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = borderRadius.toRRect(rect).deflate(0.7);

    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.95),
          Colors.white.withValues(alpha: 0.32),
          const Color(0xFF4A7FD4).withValues(alpha: 0.09),
          Colors.white.withValues(alpha: 0.78),
        ],
        stops: const [0, 0.42, 0.64, 1],
      ).createShader(rect);
    canvas.drawRRect(rrect, rim);

    final specular = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round
      ..shader = LinearGradient(
        colors: [
          Colors.white.withValues(alpha: 0),
          Colors.white.withValues(alpha: 0.92),
          Colors.white.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width * 0.74, size.height));
    final path = Path()
      ..moveTo(size.width * 0.12, size.height * 0.18)
      ..cubicTo(
        size.width * 0.34,
        size.height * 0.03,
        size.width * 0.62,
        size.height * 0.05,
        size.width * 0.83,
        size.height * 0.18,
      );
    canvas.drawPath(path, specular);

    final bottomShade = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          const Color(0xFF475569).withValues(alpha: 0.065),
        ],
      ).createShader(
          Rect.fromLTWH(0, size.height * 0.45, size.width, size.height * 0.55));
    canvas.drawRRect(rrect, bottomShade);
  }

  @override
  bool shouldRepaint(covariant _LiquidGlassPainter oldDelegate) =>
      oldDelegate.borderRadius != borderRadius;
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
    final fill = surface == GlassSurface.nav
        ? Colors.white.withValues(alpha: 0.74)
        : surface == GlassSurface.flat
            ? Colors.white.withValues(alpha: 0.72)
            : Colors.white.withValues(alpha: 0.78);
    final shadow = boxShadow ??
        (surface == GlassSurface.nav
            ? HiVpnGlass.shadowNav
            : HiVpnGlass.shadow);
    Widget panel = RepaintBoundary(
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: borderRadius,
                  color: fill,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.55),
                    width: 0.55,
                  ),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withValues(alpha: 0.84),
                      const Color(0xFFF8FBFF).withValues(alpha: 0.56),
                      const Color(0xFFEAF1FA).withValues(alpha: 0.34),
                    ],
                    stops: const [0, 0.5, 1],
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
                      Colors.white.withValues(alpha: 0.10),
                      Colors.white.withValues(alpha: 0.03),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.12, 0.36],
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

    final highlightHeight = (size.height * 0.045).clamp(2.0, 12.0);
    final topHighlight = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          HiVpnGlass.innerHighlight.withValues(alpha: 0.18),
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
      ..strokeWidth = 0.45
      ..color = Colors.white.withValues(alpha: 0.38);

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
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: HiVpnGlass.baseCanvas,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFF2F6FB),
            Color(0xFFF8FAFC),
            Color(0xFFEFF4FA),
          ],
          stops: [0, 0.46, 1],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            left: -90,
            top: -70,
            width: 240,
            height: 240,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Color(0xFFB9D8FF),
                    Color(0x00B9D8FF),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: -120,
            top: 120,
            width: 280,
            height: 280,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Color(0xFFFFD8C2),
                    Color(0x00FFD8C2),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: -120,
            height: 260,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.all(Radius.circular(160)),
                gradient: RadialGradient(
                  colors: [
                    Color(0xFFCDEEDB),
                    Color(0x00CDEEDB),
                  ],
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class HiVpnSheetScaffold extends StatelessWidget {
  const HiVpnSheetScaffold({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xFFF8FBFF),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: FrostedGlass(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        padding: EdgeInsets.zero,
        surface: GlassSurface.raised,
        child: child,
      ),
    );
  }
}
