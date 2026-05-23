import 'dart:async';

import 'package:flutter/material.dart';

/// Tap-to-refresh with a single spin animation; runs [onRefresh] immediately.
class SpinRefreshButton extends StatefulWidget {
  const SpinRefreshButton({
    super.key,
    required this.onRefresh,
    this.tooltip,
    this.iconSize = 22,
    this.color,
  });

  final Future<void> Function() onRefresh;
  final String? tooltip;
  final double iconSize;
  final Color? color;

  @override
  State<SpinRefreshButton> createState() => _SpinRefreshButtonState();
}

class _SpinRefreshButtonState extends State<SpinRefreshButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    if (_controller.isAnimating) return;
    unawaited(_controller.forward(from: 0));
    await widget.onRefresh();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.onSurface;
    return IconButton(
      tooltip: widget.tooltip,
      onPressed: _handleTap,
      icon: RotationTransition(
        turns: _controller,
        child: Icon(Icons.refresh_rounded, color: color, size: widget.iconSize),
      ),
    );
  }
}