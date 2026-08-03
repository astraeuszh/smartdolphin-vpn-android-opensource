import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_codes.dart';
import '../../../core/errors/error_dialog.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/page_app_bar.dart';
import '../../../widgets/frosted_glass.dart';
import '../../session/domain/session_controller.dart';
import '../../session/domain/session_status.dart';
import '../domain/speedtest_controller.dart';
import '../domain/speedtest_state.dart';

class SpeedTestScreen extends ConsumerWidget {
  const SpeedTestScreen({super.key});

  static const _downloadColor = Color(0xFF1976D2);
  static const _uploadColor = Color(0xFFF4C430);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(speedTestControllerProvider);
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;

    ref.listen<SpeedTestState>(speedTestControllerProvider, (previous, next) {
      if ((previous?.isBusy ?? false) &&
          next.status == SpeedTestStatus.error &&
          next.errorMessage != null &&
          context.mounted) {
        showErrorDialog(
          context,
          message: next.errorMessage!,
          errorCode: ecLocalNetDisconnected,
          title: l10n.navSpeedTest,
        );
      }
    });

    final button = _PrimaryButtonInfo.fromState(state, l10n);
    return Scaffold(
      backgroundColor: dark ? const Color(0xFF0B0D0F) : const Color(0xFFF4F6F7),
      appBar: HiVpnPageAppBar(title: l10n.navSpeedTest),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 120),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Column(
                  children: [
                    _TestHeader(state: state, l10n: l10n),
                    const SizedBox(height: 4),
                    Text(
                      _speedRangeText(context),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _ChartWorkspace(
                      state: state,
                      l10n: l10n,
                      downloadColor: _downloadColor,
                      uploadColor: _uploadColor,
                    ),
                    if (state.errorMessage != null) ...[
                      const SizedBox(height: 12),
                      _ErrorBanner(message: state.errorMessage!),
                    ],
                    const SizedBox(height: 14),
                    _MetricStrip(state: state, l10n: l10n),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: FilledButton.icon(
                        onPressed: button.enabled
                            ? () {
                                final connected = ref
                                        .read(sessionControllerProvider)
                                        .status ==
                                    SessionStatus.connected;
                                ref
                                    .read(speedTestControllerProvider.notifier)
                                    .run(isVpnTest: connected);
                              }
                            : null,
                        icon: Icon(button.icon),
                        label: Text(button.label),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TestHeader extends StatelessWidget {
  const _TestHeader({required this.state, required this.l10n});

  final SpeedTestState state;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = _networkText(context, state.isVpnTest, state.isBusy);
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: .12),
            shape: BoxShape.circle,
          ),
          child: Icon(
            state.isVpnTest ? Icons.shield_rounded : Icons.wifi_rounded,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                _networkText(context, state.isVpnTest, false),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (state.isBusy)
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
      ],
    );
  }
}

class _ChartWorkspace extends StatelessWidget {
  const _ChartWorkspace({
    required this.state,
    required this.l10n,
    required this.downloadColor,
    required this.uploadColor,
  });

  final SpeedTestState state;
  final AppLocalizations l10n;
  final Color downloadColor;
  final Color uploadColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final download = state.downloadMbps;
    final upload = state.uploadMbps;
    final active = state.phase == SpeedTestPhase.download
        ? state.liveMbps
        : state.phase == SpeedTestPhase.upload
            ? state.liveMbps
            : math.max(download, upload);
    const scale = 500.0;

    return FrostedGlass(
      borderRadius: BorderRadius.circular(24),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      surface: GlassSurface.raised,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _LiveReading(
                  label: l10n.speedTestCardDownloadLabel,
                  value: state.phase == SpeedTestPhase.download
                      ? state.liveMbps
                      : state.downloadMbps,
                  color: downloadColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _LiveReading(
                  label: l10n.speedTestCardUploadLabel,
                  value: state.phase == SpeedTestPhase.upload
                      ? state.liveMbps
                      : state.uploadMbps,
                  color: uploadColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 230,
            child: _SpeedGauge(
              value: active,
              scale: scale,
              color: state.phase == SpeedTestPhase.upload
                  ? uploadColor
                  : downloadColor,
              busy: state.isBusy,
              label: state.phase == SpeedTestPhase.upload
                  ? l10n.speedTestCardUploadLabel
                  : l10n.speedTestCardDownloadLabel,
            ),
          ),
        ],
      ),
    );
  }
}

String _networkText(BuildContext context, bool vpn, bool testing) {
  final language = Localizations.localeOf(context).languageCode;
  const copy = <String, List<String>>{
    'zh': ['当前是 VPN 网络', '当前是本地网络', '正在测试 VPN 网络', '正在测试本地网络'],
    'es': [
      'Red VPN actual',
      'Red local actual',
      'Probando red VPN',
      'Probando red local'
    ],
    'ja': [
      '現在は VPN ネットワーク',
      '現在はローカルネットワーク',
      'VPN ネットワークをテスト中',
      'ローカルネットワークをテスト中'
    ],
    'en': [
      'Current VPN network',
      'Current local network',
      'Testing VPN network',
      'Testing local network'
    ],
  };
  final values = copy[language] ?? copy['en']!;
  return values[testing ? (vpn ? 2 : 3) : (vpn ? 0 : 1)];
}

String _speedRangeText(BuildContext context) {
  return switch (Localizations.localeOf(context).languageCode) {
    'zh' => '当前测速范围是 0~500Mbps，超过测不了',
    'es' => 'El rango actual es 0~500 Mbps; no se puede medir mas.',
    'ja' => '現在の測定範囲は 0~500 Mbps です。上限を超えて測定できません。',
    _ =>
      'Current test range is 0~500 Mbps. Speeds above it cannot be measured.',
  };
}

class _SpeedGauge extends StatelessWidget {
  const _SpeedGauge({
    required this.value,
    required this.scale,
    required this.color,
    required this.busy,
    required this.label,
  });

  final double value;
  final double scale;
  final Color color;
  final bool busy;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CustomPaint(
      painter: _GaugePainter(
        progress: scale <= 0 ? 0 : (value / scale).clamp(0, 1),
        color: color,
        track: theme.colorScheme.outlineVariant.withValues(alpha: .5),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.only(top: 48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${value.toStringAsFixed(1)} Mbps',
                  style: theme.textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w800, color: color)),
              const SizedBox(height: 4),
              Text(busy ? label : '0~${scale.toStringAsFixed(0)} Mbps',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  const _GaugePainter(
      {required this.progress, required this.color, required this.track});
  final double progress;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * .7);
    final radius = math.min(size.width * .36, size.height * .58);
    final rect = Rect.fromCircle(center: center, radius: radius);
    const start = math.pi * .75;
    const sweep = math.pi * 1.5;
    final trackPaint = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, start, sweep, false, trackPaint);
    final valuePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, start, sweep * progress, false, valuePaint);
    final angle = start + sweep * progress;
    final needle = Offset(
      center.dx + math.cos(angle) * radius,
      center.dy + math.sin(angle) * radius,
    );
    canvas.drawCircle(needle, 7, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.track != track;
}

class _LiveReading extends StatelessWidget {
  const _LiveReading({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
                width: 8,
                height: 8,
                decoration:
                    BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            '${value.toStringAsFixed(1)} Mbps',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

class _MetricStrip extends StatelessWidget {
  const _MetricStrip({required this.state, required this.l10n});
  final SpeedTestState state;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final downloadPeak = state.downloadSeries.isEmpty
        ? 0.0
        : state.downloadSeries.reduce(math.max);
    final uploadPeak =
        state.uploadSeries.isEmpty ? 0.0 : state.uploadSeries.reduce(math.max);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF15191C) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: dark ? const Color(0xFF282E33) : const Color(0xFFE1E5E8),
        ),
      ),
      child: Row(
        children: [
          _Metric(
            label: l10n.speedTestCardLatencyLabel,
            value:
                state.ping == null ? '--' : '${state.ping!.inMilliseconds} ms',
          ),
          _divider(theme),
          _Metric(
            label: l10n.speedTestCardDownloadLabel,
            value: '${downloadPeak.toStringAsFixed(1)} Mbps',
          ),
          _divider(theme),
          _Metric(
            label: l10n.speedTestCardUploadLabel,
            value: '${uploadPeak.toStringAsFixed(1)} Mbps',
          ),
        ],
      ),
    );
  }

  Widget _divider(ThemeData theme) => Container(
        width: 1,
        height: 34,
        margin: const EdgeInsets.symmetric(horizontal: 8),
        color: theme.colorScheme.outlineVariant,
      );
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 5),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value,
                style: theme.textTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.error.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.error.withValues(alpha: .28)),
      ),
      child: Text(message, style: TextStyle(color: colors.error)),
    );
  }
}

String _phaseLabel(SpeedTestState state, AppLocalizations l10n) {
  return switch (state.phase) {
    SpeedTestPhase.locating => l10n.speedTestCardLocating,
    SpeedTestPhase.ping => l10n.speedTestCardLatencyLabel,
    SpeedTestPhase.download => l10n.speedTestCardDownloadMeasure,
    SpeedTestPhase.upload => l10n.speedTestCardUploadMeasure,
    SpeedTestPhase.idle => switch (state.status) {
        SpeedTestStatus.complete => l10n.speedTestCompleted,
        SpeedTestStatus.error => l10n.speedTestTapRetry,
        SpeedTestStatus.preparing => l10n.speedTestPreparingShort,
        _ => l10n.speedTestReady,
      },
  };
}

class _PrimaryButtonInfo {
  const _PrimaryButtonInfo(this.label, this.icon, this.enabled);
  final String label;
  final IconData icon;
  final bool enabled;

  factory _PrimaryButtonInfo.fromState(
      SpeedTestState state, AppLocalizations l10n) {
    return switch (state.status) {
      SpeedTestStatus.preparing => _PrimaryButtonInfo(
          l10n.speedTestPreparingShort, Icons.hourglass_top_rounded, false),
      SpeedTestStatus.running => _PrimaryButtonInfo(
          l10n.speedTestCardTesting, Icons.monitor_heart_outlined, false),
      SpeedTestStatus.complete =>
        _PrimaryButtonInfo(l10n.speedTestRunAgain, Icons.replay_rounded, true),
      SpeedTestStatus.error => _PrimaryButtonInfo(
          l10n.speedTestRetryTest, Icons.refresh_rounded, true),
      SpeedTestStatus.idle => _PrimaryButtonInfo(
          l10n.speedTestStartTest, Icons.play_arrow_rounded, true),
    };
  }
}
