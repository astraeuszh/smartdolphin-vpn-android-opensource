import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/ui/top_snack.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/remote/console_auth.dart';
import '../../../services/remote/console_qr_auth.dart';
import '../domain/auth_controller.dart';

class QrScanScreen extends ConsumerStatefulWidget {
  const QrScanScreen({super.key});

  @override
  ConsumerState<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends ConsumerState<QrScanScreen>
    with SingleTickerProviderStateMixin {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );
  bool _busy = false;
  bool _paused = false;
  late AnimationController _lineController;

  static const _frameSize = 260.0;

  @override
  void initState() {
    super.initState();
    _lineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _lineController.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy || _paused) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || raw.isEmpty) return;
    final challengeId = ConsoleQrAuth.parseChallengeId(raw);
    if (challengeId == null) return;

    setState(() {
      _busy = true;
      _paused = true;
    });
    await _controller.stop();

    unawaited(SystemSound.play(SystemSoundType.click));
    unawaited(HapticFeedback.mediumImpact());

    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final approved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.authQrApproveTitle),
        content: Text(l10n.authQrApproveMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.authQrApproveConfirm),
          ),
        ],
      ),
    );

    if (approved != true) {
      if (mounted) {
        setState(() {
          _busy = false;
          _paused = false;
        });
        await _controller.start();
      }
      return;
    }

    try {
      await ref.read(authControllerProvider.notifier).approveQrLogin(challengeId);
      if (!mounted) return;
      unawaited(SystemSound.play(SystemSoundType.alert));
      showTopSnackBar(context, l10n.authQrApproveOk);
      Navigator.of(context).pop(true);
    } on ConsoleAuthException catch (e) {
      if (!mounted) return;
      showTopSnackBar(
        context,
        e.message.isNotEmpty ? e.message : l10n.authLoginRequired,
        isError: true,
      );
      setState(() {
        _busy = false;
        _paused = false;
      });
      await _controller.start();
    } catch (e) {
      if (!mounted) return;
      showTopSnackBar(context, '$e', isError: true);
      setState(() {
        _busy = false;
        _paused = false;
      });
      await _controller.start();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.authQrScanTitle),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          Column(
            children: [
              const Expanded(child: ColoredBox(color: Color(0x99000000))),
              Row(
                children: [
                  const Expanded(child: ColoredBox(color: Color(0x99000000))),
                  SizedBox(
                    width: _frameSize,
                    height: _frameSize,
                    child: Stack(
                      children: [
                        CustomPaint(
                          size: const Size(_frameSize, _frameSize),
                          painter: _ScanFramePainter(color: theme.colorScheme.primary),
                        ),
                        AnimatedBuilder(
                          animation: _lineController,
                          builder: (context, _) {
                            final y = 12 + (_frameSize - 24) * _lineController.value;
                            return Positioned(
                              left: 16,
                              right: 16,
                              top: y,
                              child: Container(
                                height: 2,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.transparent,
                                      theme.colorScheme.primary.withValues(alpha: 0.95),
                                      Colors.transparent,
                                    ],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: theme.colorScheme.primary.withValues(alpha: 0.55),
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const Expanded(child: ColoredBox(color: Color(0x99000000))),
                ],
              ),
              const Expanded(child: ColoredBox(color: Color(0x99000000))),
            ],
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              color: theme.colorScheme.surface.withValues(alpha: 0.92),
              padding: const EdgeInsets.all(20),
              child: Text(
                l10n.authQrScanHint,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ),
          if (_busy)
            const ColoredBox(
              color: Color(0x66000000),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}

class _ScanFramePainter extends CustomPainter {
  _ScanFramePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const corner = 28.0;
    final w = size.width;
    final h = size.height;

    void cornerLines(double x, double y, bool flipX, bool flipY) {
      final dx = flipX ? -1.0 : 1.0;
      final dy = flipY ? -1.0 : 1.0;
      canvas.drawLine(Offset(x, y), Offset(x + dx * corner, y), paint);
      canvas.drawLine(Offset(x, y), Offset(x, y + dy * corner), paint);
    }

    cornerLines(0, 0, false, false);
    cornerLines(w, 0, true, false);
    cornerLines(0, h, false, true);
    cornerLines(w, h, true, true);
  }

  @override
  bool shouldRepaint(covariant _ScanFramePainter oldDelegate) =>
      oldDelegate.color != color;
}
