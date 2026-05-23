import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/colors.dart';

enum ConnectButtonVisualState { idle, connecting, active }

/// 第一版：毛玻璃内凹圆盘 + 完整渐变蓝圈（连接时旋转）
class ConnectControl extends StatefulWidget {
  const ConnectControl({
    super.key,
    required this.enabled,
    required this.onTap,
    required this.label,
    this.isActive = false,
    this.isLoading = false,
    this.statusText,
    this.visualState = ConnectButtonVisualState.idle,
  });

  final bool enabled;
  final Future<void> Function()? onTap;
  final String label;
  final bool isActive;
  final bool isLoading;
  @Deprecated('Unused')
  final String? statusText;
  final ConnectButtonVisualState visualState;

  @override
  State<ConnectControl> createState() => _ConnectControlState();
}

class _ConnectControlState extends State<ConnectControl>
    with TickerProviderStateMixin {
  late final AnimationController _rotateController;
  late final AnimationController _pressController;

  @override
  void initState() {
    super.initState();
    _rotateController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 90),
      reverseDuration: const Duration(milliseconds: 140),
    );
  }

  @override
  void didUpdateWidget(covariant ConnectControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncRingAnimation();
  }

  void _syncRingAnimation() {
    final isConnecting =
        widget.visualState == ConnectButtonVisualState.connecting;
    if (isConnecting) {
      if (!_rotateController.isAnimating) {
        _rotateController.repeat();
      }
    } else {
      if (_rotateController.isAnimating) {
        _rotateController.stop();
        _rotateController.value = 0;
      }
    }
  }

  @override
  void dispose() {
    _rotateController.dispose();
    _pressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDisabled = !widget.enabled;
    final isConnecting = widget.visualState == ConnectButtonVisualState.connecting;
    final isActive = widget.visualState == ConnectButtonVisualState.active;
    _syncRingAnimation();

    final accent = isActive ? HiVpnColors.success : HiVpnColors.accent;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) {
        if (!isDisabled) {
          HapticFeedback.lightImpact();
          _pressController.forward();
        }
      },
      onTapUp: (_) => _pressController.reverse(),
      onTapCancel: () => _pressController.reverse(),
      onTap: isDisabled ? null : () => widget.onTap?.call(),
      child: AnimatedBuilder(
        animation: _pressController,
        builder: (context, _) {
          final pressed = _pressController.value;
          final scale = isConnecting ? 1.02 : (1.0 - 0.04 * pressed);
          return Transform.scale(
            scale: scale,
            child: _buildBody(theme, accent, isDisabled, isConnecting, pressed),
          );
        },
      ),
    );
  }

  Widget _buildBody(
    ThemeData theme,
    Color accent,
    bool isDisabled,
    bool isConnecting,
    double pressed,
  ) {
    const size = 180.0;
    const innerPadding = 24.0;
    final innerSize = size - innerPadding * 2;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          AnimatedBuilder(
            animation: _rotateController,
            builder: (context, _) {
              final angle = _rotateController.value * 2 * pi;
              return CustomPaint(
                size: Size(size, size),
                painter: _RingPainter(
                  rotation: isConnecting ? angle : 0,
                  strokeWidth: 3,
                  accentColor: accent,
                  glowOpacity: 0.12 + 0.18 * pressed,
                ),
              );
            },
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(innerSize / 2),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                width: innerSize,
                height: innerSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.surface.withValues(alpha: 0.9),
                  border: Border.all(
                    color: accent.withValues(alpha: 0.25),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(
                        alpha: isConnecting ? 0.25 : 0.1,
                      ),
                      blurRadius: isConnecting ? 28 : 18,
                      spreadRadius: isConnecting ? 2 : 0,
                    ),
                    BoxShadow(
                      color: theme.colorScheme.shadow.withValues(alpha: 0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: isConnecting
                    ? SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          valueColor: AlwaysStoppedAnimation<Color>(accent),
                        ),
                      )
                    : Text(
                        widget.label,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          color: isDisabled
                              ? theme.colorScheme.onSurface
                                  .withValues(alpha: 0.4)
                              : theme.colorScheme.onSurface,
                        ),
                        textAlign: TextAlign.center,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 细圆环：渐变描边 + 外发光
class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.rotation,
    required this.strokeWidth,
    required this.accentColor,
    required this.glowOpacity,
  });

  final double rotation;
  final double strokeWidth;
  final Color accentColor;
  final double glowOpacity;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - strokeWidth / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final gradient = SweepGradient(
      startAngle: rotation,
      endAngle: rotation + 2 * pi,
      colors: [
        accentColor,
        Color.lerp(accentColor, HiVpnColors.info, 0.5)!,
        accentColor,
      ],
    );

    final glowPaint = Paint()
      ..shader = SweepGradient(
        startAngle: rotation,
        endAngle: rotation + 2 * pi,
        colors: [
          accentColor.withValues(alpha: glowOpacity),
          HiVpnColors.info.withValues(alpha: glowOpacity * 0.6),
          accentColor.withValues(alpha: glowOpacity),
        ],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth + 8
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawCircle(center, radius, glowPaint);

    final mainPaint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, mainPaint);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      rotation != old.rotation ||
      strokeWidth != old.strokeWidth ||
      accentColor != old.accentColor ||
      glowOpacity != old.glowOpacity;
}
