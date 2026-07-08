import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_codes.dart';
import '../../../core/errors/error_dialog.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/colors.dart';
import '../../../widgets/frosted_glass.dart';
import '../../../widgets/page_app_bar.dart';
import '../../session/domain/session_controller.dart';
import '../../session/domain/session_status.dart';
import '../domain/speedtest_controller.dart';
import '../domain/speedtest_state.dart';
import 'widgets/speed_gauge.dart';

class SpeedTestScreen extends ConsumerWidget {
  const SpeedTestScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(speedTestControllerProvider);
    final controller = ref.read(speedTestControllerProvider.notifier);
    final l10n = context.l10n;
    ref.listen<SpeedTestState>(speedTestControllerProvider, (prev, next) {
      if (prev?.status == SpeedTestStatus.running ||
          prev?.status == SpeedTestStatus.preparing) {
        if (next.status == SpeedTestStatus.error && next.errorMessage != null && context.mounted) {
          showErrorDialog(
            context,
            message: next.errorMessage!,
            errorCode: ecLocalNetDisconnected,
            title: l10n.navSpeedTest,
          );
        }
      }
    });
    final theme = Theme.of(context);

    final buttonInfo = _PrimaryButtonInfo.fromState(state, l10n);
    final gaugeLabel = _gaugeLabel(state, l10n);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: HiVpnPageAppBar(title: l10n.navSpeedTest),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 160),
          children: [
            Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _ModeBadge(state: state, l10n: l10n),
                      const SizedBox(height: 16),
                    _GaugePanel(
                      state: state,
                      gaugeLabel: gaugeLabel,
                      buttonInfo: buttonInfo,
                      l10n: l10n,
                      onRun: buttonInfo.enabled
                          ? () {
                              final isVpn = ref.read(sessionControllerProvider).status ==
                                  SessionStatus.connected;
                              controller.run(isVpnTest: isVpn);
                            }
                          : null,
                    ),
                    if (state.errorMessage != null) ...[
                      const SizedBox(height: 20),
                      _ErrorBanner(message: state.errorMessage!),
                    ],
                    const SizedBox(height: 28),
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 250),
                      opacity: state.isBusy ? 0.6 : 1,
                      child: _MetricGrid(state: state, l10n: l10n),
                    ),
                    const SizedBox(height: 32),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: state.hasResult
                          ? _ScoreView(
                              key: ValueKey(state.lastRun ?? state.downloadMbps),
                              state: state,
                              l10n: l10n,
                            )
                          : const SizedBox.shrink(),
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

class _GaugePanel extends StatelessWidget {
  const _GaugePanel({
    required this.state,
    required this.gaugeLabel,
    required this.buttonInfo,
    required this.l10n,
    this.onRun,
  });

  final SpeedTestState state;
  final String gaugeLabel;
  final _PrimaryButtonInfo buttonInfo;
  final AppLocalizations l10n;
  final VoidCallback? onRun;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FrostedGlass(
      borderRadius: BorderRadius.circular(32),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      surface: GlassSurface.raised,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PhaseStrip(state: state, l10n: l10n),
          if (state.serverName != null && state.serverName!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              state.serverName!,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 8),
          Center(
            child: SpeedGauge(
              needleValue: state.gaugeNeedleValue,
              displayValue: state.gaugeDisplayValue,
              maxValue: state.gaugeMax,
              statusLabel: gaugeLabel,
              isActive: state.status == SpeedTestStatus.running,
              tickStep: 100,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed: onRun,
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
              icon: Icon(buttonInfo.icon),
              label: Text(buttonInfo.label),
            ),
          ),
          if (state.status == SpeedTestStatus.preparing ||
              state.phase == SpeedTestPhase.locating) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    state.isVpnTest ? l10n.speedTestPreparingTunnel : l10n.speedTestPreparingLocal,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                ),
              ],
            ),
          ] else if (state.status == SpeedTestStatus.running) ...[
            const SizedBox(height: 14),
            Text(
              _runningPhaseLabel(state, l10n),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.7),
              ),
              textAlign: TextAlign.center,
            ),
          ] else if (state.status == SpeedTestStatus.complete && state.downloadMbps <= 0) ...[
            const SizedBox(height: 14),
            Text(
              l10n.speedTestRunToGetValues,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.state, required this.l10n});

  final SpeedTestState state;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final isTwoColumn = maxWidth >= 460;
        final itemWidth = isTwoColumn ? (maxWidth - 16) / 2 : maxWidth;

        return Wrap(
          spacing: 16,
          runSpacing: 16,
          alignment: WrapAlignment.center,
          children: [
            SizedBox(
              width: itemWidth,
              child: _MetricCard(
                title: l10n.speedTestCardDownloadLabel,
                value: state.downloadMbps > 0
                    ? '${state.downloadMbps.toStringAsFixed(1)} Mbps'
                    : (state.isBusy ? l10n.speedTestMeasuring : '--'),
                icon: Icons.download_rounded,
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: _MetricCard(
                title: l10n.speedTestCardUploadLabel,
                value: state.uploadMbps > 0.05
                    ? '${state.uploadMbps.toStringAsFixed(1)} Mbps'
                    : (state.isBusy && state.phase == SpeedTestPhase.upload
                        ? l10n.speedTestMeasuring
                        : (state.isBusy ? l10n.speedTestPending : '--')),
                icon: Icons.upload_rounded,
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: _MetricCard(
                title: l10n.speedTestCardLatencyLabel,
                value: state.ping != null
                    ? '${state.ping!.inMilliseconds} ms'
                    : (state.isBusy ? l10n.speedTestMeasuring : '--'),
                icon: Icons.podcasts,
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: _MetricCard(
                title: l10n.speedTestIpLabel,
                value: state.ip != null && state.ip!.isNotEmpty
                    ? state.ip!
                    : (state.isBusy ? l10n.speedTestDetecting : l10n.speedTestNotAvailable),
                icon: Icons.language,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ModeBadge extends StatelessWidget {
  const _ModeBadge({required this.state, required this.l10n});

  final SpeedTestState state;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isVpn = state.isVpnTest;
    final fg = theme.colorScheme.onSurfaceVariant;
    return Center(
      child: FrostedGlass(
        borderRadius: BorderRadius.circular(999),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        surface: GlassSurface.flat,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isVpn ? Icons.shield_rounded : Icons.wifi_rounded,
              size: 16,
              color: fg,
            ),
            const SizedBox(width: 8),
            Text(
              isVpn ? l10n.statusConnected : l10n.speedTestBenchmarkingLocal,
              style: theme.textTheme.labelMedium?.copyWith(
                color: fg,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhaseStrip extends StatelessWidget {
  const _PhaseStrip({required this.state, required this.l10n});

  final SpeedTestState state;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final phases = [
      (SpeedTestPhase.locating, l10n.speedTestCardLocating),
      (SpeedTestPhase.ping, l10n.speedTestCardLatencyLabel),
      (SpeedTestPhase.download, l10n.speedTestCardDownloadLabel),
      (SpeedTestPhase.upload, l10n.speedTestCardUploadLabel),
    ];
    int activeIndex = 0;
    if (state.isBusy || state.status == SpeedTestStatus.complete) {
      activeIndex = switch (state.phase) {
        SpeedTestPhase.ping => 1,
        SpeedTestPhase.download => 2,
        SpeedTestPhase.upload => 3,
        SpeedTestPhase.locating => 0,
        SpeedTestPhase.idle => state.status == SpeedTestStatus.complete ? 3 : 0,
      };
    }

    return Row(
      children: [
        for (var i = 0; i < phases.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: i <= activeIndex
                      ? theme.colorScheme.primary.withValues(alpha: 0.8)
                      : theme.colorScheme.outline.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          _PhaseChip(
            label: phases[i].$2,
            active: i == activeIndex && state.isBusy,
            done: i < activeIndex || state.status == SpeedTestStatus.complete,
          ),
        ],
      ],
    );
  }
}

class _PhaseChip extends StatelessWidget {
  const _PhaseChip({
    required this.label,
    required this.active,
    required this.done,
  });

  final String label;
  final bool active;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = active
        ? theme.colorScheme.primary
        : done
            ? theme.colorScheme.primary.withValues(alpha: 0.65)
            : theme.colorScheme.onSurface.withValues(alpha: 0.45);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active || done ? color : Colors.transparent,
            border: Border.all(color: color, width: 1.6),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            fontSize: 10,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

String _gaugeLabel(SpeedTestState state, AppLocalizations l10n) {
  switch (state.phase) {
    case SpeedTestPhase.locating:
      return l10n.speedTestCardLocating;
    case SpeedTestPhase.ping:
      return l10n.speedTestCardLatencyLabel;
    case SpeedTestPhase.download:
      return l10n.speedTestCardDownloadLabel;
    case SpeedTestPhase.upload:
      return l10n.speedTestCardUploadLabel;
    case SpeedTestPhase.idle:
      break;
  }
  switch (state.status) {
    case SpeedTestStatus.preparing:
      return l10n.speedTestPreparingShort;
    case SpeedTestStatus.running:
      return l10n.speedTestCardTesting;
    case SpeedTestStatus.complete:
      return state.hasResult ? l10n.speedTestResult : l10n.speedTestCompleted;
    case SpeedTestStatus.error:
      return l10n.speedTestTapRetry;
    case SpeedTestStatus.idle:
    default:
      return l10n.speedTestReady;
  }
}

String _runningPhaseLabel(SpeedTestState state, AppLocalizations l10n) {
  return switch (state.phase) {
    SpeedTestPhase.locating => l10n.speedTestCheckLatency,
    SpeedTestPhase.ping => l10n.speedTestCardLatencyLabel,
    SpeedTestPhase.download => l10n.speedTestCardDownloadMeasure,
    SpeedTestPhase.upload => l10n.speedTestCardUploadMeasure,
    SpeedTestPhase.idle => l10n.speedTestCollecting,
  };
}

class _PrimaryButtonInfo {
  const _PrimaryButtonInfo({
    required this.label,
    required this.icon,
    required this.enabled,
  });

  final String label;
  final IconData icon;
  final bool enabled;

  factory _PrimaryButtonInfo.fromState(SpeedTestState state, AppLocalizations l10n) {
    switch (state.status) {
      case SpeedTestStatus.preparing:
        return _PrimaryButtonInfo(
          label: l10n.speedTestPreparingShort,
          icon: Icons.hourglass_top_rounded,
          enabled: false,
        );
      case SpeedTestStatus.running:
        return _PrimaryButtonInfo(
          label: l10n.speedTestCardTesting,
          icon: Icons.speed,
          enabled: false,
        );
      case SpeedTestStatus.complete:
        return _PrimaryButtonInfo(
          label: l10n.speedTestRunAgain,
          icon: Icons.replay_rounded,
          enabled: true,
        );
      case SpeedTestStatus.error:
        return _PrimaryButtonInfo(
          label: l10n.speedTestRetryTest,
          icon: Icons.refresh_rounded,
          enabled: true,
        );
      case SpeedTestStatus.idle:
      default:
        return _PrimaryButtonInfo(
          label: l10n.speedTestStartTest,
          icon: Icons.play_arrow_rounded,
          enabled: true,
        );
    }
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: HiVpnColors.error.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: HiVpnColors.error.withOpacity(0.2)),
      ),
      child: Text(
        message,
        style: theme.textTheme.bodyMedium?.copyWith(color: HiVpnColors.error),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _ScoreView extends StatelessWidget {
  const _ScoreView({required this.state, required this.l10n, super.key});

  final SpeedTestState state;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final score = state.networkScore;
    return FrostedGlass(
      borderRadius: BorderRadius.circular(24),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      surface: GlassSurface.raised,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.speedTestNetworkScoreLabel(score),
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            '${l10n.speedTestIpLabel}: ${state.ip ?? '--'} · '
            '${l10n.latencyLabel}: ${state.ping?.inMilliseconds ?? '--'} ms · '
            '${l10n.serverDownloadLabel}: ${state.downloadMbps.toStringAsFixed(1)} Mbps · '
            '${l10n.serverUploadLabel}: ${state.uploadMbps.toStringAsFixed(1)} Mbps',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: HiVpnColors.mutedGray.withValues(alpha: 0.18),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: theme.colorScheme.onSurfaceVariant,
            size: 20,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          title,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ],
    );

    return FrostedGlass(
      borderRadius: BorderRadius.circular(26),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      child: content,
    );
  }
}

