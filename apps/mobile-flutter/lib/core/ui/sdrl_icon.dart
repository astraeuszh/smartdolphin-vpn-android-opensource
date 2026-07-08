import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Unified SDRL brand tile: grey background + white **S**.
/// Same artwork for `.sdrl`, `.sdrb`, `sdrlc`, and SDRL Core.
class SdrlIcon extends StatelessWidget {
  const SdrlIcon({super.key, this.size = 24});

  static const assetPath = 'assets/icons/sdrl/sdrl_icon.svg';

  final double size;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      assetPath,
      width: size,
      height: size,
      semanticsLabel: 'SDRL',
    );
  }
}

/// Fallback when SVG fails — pure Flutter, same look.
class SdrlIconFallback extends StatelessWidget {
  const SdrlIconFallback({super.key, this.size = 24});

  final double size;

  @override
  Widget build(BuildContext context) {
    final radius = size * 0.16;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF9E9E9E),
        borderRadius: BorderRadius.circular(radius),
      ),
      alignment: Alignment.center,
      child: Text(
        'S',
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.58,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}
