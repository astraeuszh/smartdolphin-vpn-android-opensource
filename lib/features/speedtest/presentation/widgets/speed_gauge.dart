import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Semicircle speedometer: 0 on the LEFT, max on the RIGHT, needle with settle wobble.
class SpeedGauge extends StatefulWidget {
  const SpeedGauge({
    super.key,
    required this.value,
    this.maxValue = 180,
    this.statusLabel = '',
    this.isActive = false,
    this.tickStep = 30,
  });

  final double value;
  final double maxValue;
  final String statusLabel;
  final bool isActive;
  final int tickStep;

  @override
  State<SpeedGauge> createState() => _SpeedGaugeState();
}

class _SpeedGaugeState extends State<SpeedGauge> with SingleTickerProviderStateMixin {
  late AnimationController _settleController;
  double _displayValue = 0;

  @override
  void initState() {
    super.initState();
    _displayValue = widget.value;
    _settleController = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    _settleController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SpeedGauge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((widget.value - _displayValue).abs() > 0.05 || widget.isActive != oldWidget.isActive) {
      _animateTo(widget.value, settle: widget.isActive && !oldWidget.isActive);
    }
  }

  void _animateTo(double target, {bool settle = false}) {
    _settleController.stop();
    final from = _displayValue;
    final duration = settle
        ? const Duration(milliseconds: 900)
        : Duration(milliseconds: (200 + (target - from).abs() * 8).clamp(250, 700).toInt());
    final curve = settle ? Curves.elasticOut : Curves.easeOutCubic;
    _settleController.duration = duration;
    final anim = Tween<double>(begin: from, end: target).animate(
      CurvedAnimation(parent: _settleController, curve: curve),
    );
    _settleController.reset();
    void listener() {
      if (mounted) setState(() => _displayValue = anim.value);
    }

    anim.addListener(listener);
    _settleController.forward().whenComplete(() {
      anim.removeListener(listener);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final normalized = (widget.maxValue <= 0 ? 0 : _displayValue / widget.maxValue).clamp(0.0, 1.0);

    return SizedBox(
      width: 300,
      height: 170,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          CustomPaint(
            size: const Size(300, 150),
            painter: _SemicircleGaugePainter(
              progress: normalized.toDouble(),
              maxValue: widget.maxValue,
              tickStep: widget.tickStep,
              trackColor: theme.colorScheme.outline.withValues(alpha: 0.25),
              progressColor: theme.colorScheme.primary,
              labelStyle: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ) ??
                  const TextStyle(fontSize: 10),
            ),
          ),
          Positioned(
            bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _displayValue <= 0 ? '--' : _displayValue.toStringAsFixed(1),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'Mbps',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
                if (widget.statusLabel.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    widget.statusLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SemicircleGaugePainter extends CustomPainter {
  _SemicircleGaugePainter({
    required this.progress,
    required this.maxValue,
    required this.tickStep,
    required this.trackColor,
    required this.progressColor,
    required this.labelStyle,
  });

  final double progress;
  final double maxValue;
  final int tickStep;
  final Color trackColor;
  final Color progressColor;
  final TextStyle labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height);
    final radius = size.width / 2 - 18;

    const startAngle = -math.pi;
    const sweepAngle = math.pi;

    final arcRect = Rect.fromCircle(center: center, radius: radius);
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(arcRect, startAngle, sweepAngle, false, trackPaint);

    if (progress > 0) {
      final progressPaint = Paint()
        ..color = progressColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(arcRect, startAngle, sweepAngle * progress, false, progressPaint);
    }

    final tickCount = (maxValue / tickStep).round();
    for (var i = 0; i <= tickCount; i++) {
      final tickValue = i * tickStep;
      final t = (tickValue / maxValue).clamp(0.0, 1.0);
      final angle = startAngle + sweepAngle * t;
      final inner = radius - 6;
      final outer = radius + (i % 3 == 0 ? 8 : 4);
      final p1 = Offset(center.dx + inner * math.cos(angle), center.dy + inner * math.sin(angle));
      final p2 = Offset(center.dx + outer * math.cos(angle), center.dy + outer * math.sin(angle));
      canvas.drawLine(
        p1,
        p2,
        Paint()
          ..color = progressColor.withValues(alpha: i % 3 == 0 ? 0.85 : 0.45)
          ..strokeWidth = i % 3 == 0 ? 2.2 : 1.2
          ..strokeCap = StrokeCap.round,
      );

      if (i % 3 == 0 || tickStep <= 10) {
        final label = tickValue.toInt().toString();
        final labelR = radius + 22;
        final tp = TextPainter(
          text: TextSpan(text: label, style: labelStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        final lp = Offset(
          center.dx + labelR * math.cos(angle) - tp.width / 2,
          center.dy + labelR * math.sin(angle) - tp.height / 2,
        );
        tp.paint(canvas, lp);
      }
    }

    final needleAngle = startAngle + sweepAngle * progress;
    final needleLen = radius - 14;
    final tip = Offset(
      center.dx + needleLen * math.cos(needleAngle),
      center.dy + needleLen * math.sin(needleAngle),
    );
    final needlePaint = Paint()
      ..color = progressColor
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(center, tip, needlePaint);
    canvas.drawCircle(center, 7, Paint()..color = progressColor);
    canvas.drawCircle(center, 3.5, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _SemicircleGaugePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.maxValue != maxValue ||
        oldDelegate.progressColor != progressColor;
  }
}
