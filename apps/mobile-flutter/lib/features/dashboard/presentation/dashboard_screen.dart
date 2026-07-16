import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/colors.dart';
import '../../../widgets/frosted_glass.dart';
import '../../../widgets/spin_refresh_button.dart';
import '../../../services/haptics/haptics_service.dart';
import '../../../widgets/page_app_bar.dart';
import '../../connection/domain/tunnel_throughput_provider.dart';
import '../../usage/data_usage_controller.dart';
import '../domain/ip_info_provider.dart';
import '../domain/traffic_history_provider.dart';
import '../domain/memory_provider.dart';
import '../domain/website_latency_provider.dart'
    show
        websiteLatencyProvider,
        websiteTargets,
        LatencyResult,
        LatencySuccess,
        LatencyTimeout,
        LatencyError;
import '../../settings/presentation/settings_picker_sheet.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  String _usagePeriodKey = 'all';
  bool _ipHidden = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final throughput = ref.watch(tunnelThroughputProvider);
    final usage = ref.watch(dataUsageControllerProvider);
    final trafficHistory = ref.watch(trafficHistoryProvider);
    final ipAsync = ref.watch(ipInfoProvider);

    return Scaffold(
      appBar: HiVpnPageAppBar(title: l10n.navDashboard),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
          children: [
            _buildTrafficTrendCard(context, throughput, trafficHistory),
            const SizedBox(height: 16),
            _buildWebsiteTestCard(context, l10n),
            const SizedBox(height: 16),
            _buildIpInfoCard(context, ipAsync),
            const SizedBox(height: 16),
            _buildUsageStatsCard(context, usage),
          ],
        ),
      ),
    );
  }

  Widget _buildWebsiteTestCard(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final latencyState = ref.watch(websiteLatencyProvider);
    final controller = ref.read(websiteLatencyProvider.notifier);

    return _DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _DashboardHeaderIcon(
                icon: Icons.wifi_tethering_rounded,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.dashboardWebsiteTest,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              SpinRefreshButton(
                tooltip: l10n.dashboardQuickTest,
                onRefresh: () async {
                  await ref.read(hapticsServiceProvider).selection();
                  await controller.testAll();
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: websiteTargets.map((t) {
                final result = latencyState.result(t.id);
                final testing = latencyState.isTesting(t.id);
                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: _WebsiteTestCard(
                    name: t.name,
                    id: t.id,
                    result: result,
                    testing: testing,
                    l10n: l10n,
                    onTest: () async {
                      await ref.read(hapticsServiceProvider).selection();
                      controller.testOne(t.id);
                    },
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIpInfoCard(BuildContext context, AsyncValue<IpInfo> ipAsync) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return _DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _DashboardHeaderIcon(
                icon: Icons.public_rounded,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.dashboardIpInfo,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              SpinRefreshButton(
                tooltip: l10n.dashboardRefresh,
                onRefresh: () async {
                  await ref.read(hapticsServiceProvider).selection();
                  await ref.refresh(ipInfoProvider.future);
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          ipAsync.when(
            data: (info) {
              if (info.hasData) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (info.countryCode != null)
                                Row(
                                  children: [
                                    Text(_flagEmoji(info.countryCode ?? 'US'),
                                        style: const TextStyle(fontSize: 18)),
                                    const SizedBox(width: 6),
                                    Text(info.countryNameEnglish,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                                fontWeight: FontWeight.w500)),
                                  ],
                                ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Text('${l10n.dashboardIpLabel}: ',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                              color: theme.colorScheme.onSurface
                                                  .withOpacity(0.65))),
                                  Text(
                                      _ipHidden
                                          ? '••••••••'
                                          : (info.ip ?? '--'),
                                      style: theme.textTheme.bodySmall),
                                  IconButton(
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                        minWidth: 32, minHeight: 32),
                                    icon: Icon(
                                        _ipHidden
                                            ? Icons.visibility_off
                                            : Icons.visibility,
                                        size: 18,
                                        color: theme.colorScheme.onSurface
                                            .withOpacity(0.6)),
                                    onPressed: () =>
                                        setState(() => _ipHidden = !_ipHidden),
                                  ),
                                ],
                              ),
                              if (info.asn != null) ...[
                                const SizedBox(height: 6),
                                Text('${l10n.dashboardAsn}: ${info.asn}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.onSurface
                                            .withOpacity(0.8))),
                              ],
                              const SizedBox(height: 12),
                              Text(l10n.dashboardAutoRefresh,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.onSurface
                                          .withOpacity(0.5))),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _IpInfoRow(
                                  label: l10n.dashboardIsp,
                                  value: info.isp ?? '--'),
                              _IpInfoRow(
                                  label: l10n.dashboardOrg,
                                  value: info.org ?? '--'),
                              _IpInfoRow(
                                  label: l10n.networkLocation,
                                  value: info.displayLocationEnglish),
                              _IpInfoRow(
                                  label: l10n.networkTimezone,
                                  value: info.timezone ?? '--'),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        info.countryCode != null
                            ? '${info.countryCode}, ${info.coordinates}'
                            : info.coordinates,
                        style: theme.textTheme.labelSmall?.copyWith(
                            color:
                                theme.colorScheme.onSurface.withOpacity(0.5)),
                      ),
                    ),
                  ],
                );
              }
              final errMsg = switch (info.error) {
                '__fetch_failed__' => l10n.dashboardFetchFailed,
                '__parse_failed__' => l10n.dashboardParseFailed,
                _ => info.error ?? l10n.dashboardFetchFailed,
              };
              return Text(
                errMsg,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.error),
              );
            },
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            ),
            error: (e, _) => Text('${l10n.dashboardFetchFailed}: $e',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.error)),
          ),
        ],
      ),
    );
  }

  String _flagEmoji(String code) {
    if (code.length != 2) return '';
    final base = 0x1F1E6;
    return code.toUpperCase().characters.map((c) {
      return String.fromCharCode(base + c.codeUnitAt(0) - 0x41);
    }).join();
  }

  Widget _buildTrafficTrendCard(
    BuildContext context,
    TunnelThroughputState throughput,
    TrafficHistoryState trafficHistory,
  ) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final uploadSpeed = throughput.uploadMbps ?? 0.0;
    final downloadSpeed = throughput.downloadMbps ?? 0.0;
    final hasData = trafficHistory.uploadSamples.isNotEmpty ||
        trafficHistory.downloadSamples.isNotEmpty;

    const uploadColor = Color(0xFFF59E0B);
    const downloadColor = Color(0xFF38BDF8);

    return _DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _DashboardHeaderIcon(
                icon: Icons.insights_rounded,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Text(
                l10n.dashboardTrafficTrend,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              height: 72,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(12),
              ),
              child: hasData
                  ? SizedBox(
                      height: 56,
                      child: _TrafficSparkline(
                        uploadSamples: trafficHistory.uploadSamples,
                        downloadSamples: trafficHistory.downloadSamples,
                        height: 56,
                      ),
                    )
                  : Center(
                      child: Text(
                        l10n.dashboardTrafficHint,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.5),
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _CompactStat(
                    icon: Icons.arrow_upward_rounded,
                    label: l10n.dashboardLabelUpload,
                    value: _formatSpeed(uploadSpeed),
                    color: uploadColor,
                  ),
                ),
                Container(
                    width: 1,
                    height: 32,
                    color: Colors.white.withValues(alpha: 0.45)),
                Expanded(
                  child: _CompactStat(
                    icon: Icons.arrow_downward_rounded,
                    label: l10n.dashboardLabelDownload,
                    value: _formatSpeed(downloadSpeed),
                    color: downloadColor,
                  ),
                ),
                Container(
                    width: 1,
                    height: 32,
                    color: Colors.white.withValues(alpha: 0.45)),
                Expanded(
                  child: _CompactStat(
                    icon: Icons.memory_rounded,
                    label: l10n.dashboardLabelMemory,
                    value:
                        _formatMemory(ref.watch(appMemoryProvider).valueOrNull),
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUsageStatsCard(BuildContext context, dynamic usage) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final usedGb = usage.usedBytes / (1024 * 1024 * 1024);

    final periodUsedLabel = switch (_usagePeriodKey) {
      '1day' => l10n.dashboardUsedToday,
      '1week' => l10n.dashboardUsedWeek,
      '1month' => l10n.dashboardUsedMonth,
      '1year' => l10n.dashboardUsedYear,
      _ => l10n.dashboardUsedAll,
    };

    return _DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.data_usage,
                  color: theme.colorScheme.primary, size: 22),
              const SizedBox(width: 8),
              Text(
                l10n.dashboardUsageStats,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildPeriodPicker(context),
          const SizedBox(height: 16),
          _UsageTextRow(
              label: periodUsedLabel, value: '${usedGb.toStringAsFixed(2)} GB'),
          _UsageTextRow(
              label: l10n.dashboardUsedYear,
              value: '${usedGb.toStringAsFixed(2)} GB'),
          _UsageTextRow(
              label: l10n.dashboardUsedAll,
              value: '${usedGb.toStringAsFixed(2)} GB'),
        ],
      ),
    );
  }

  Widget _buildPeriodPicker(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final options = [
      SettingsPickerOption(value: '1day', label: l10n.dashboardPeriod1Day),
      SettingsPickerOption(value: '1week', label: l10n.dashboardPeriod1Week),
      SettingsPickerOption(value: '1month', label: l10n.dashboardPeriod1Month),
      SettingsPickerOption(value: '1year', label: l10n.dashboardPeriod1Year),
      SettingsPickerOption(value: 'all', label: l10n.dashboardPeriodAll),
    ];
    final displayLabel = switch (_usagePeriodKey) {
      '1day' => l10n.dashboardPeriod1Day,
      '1week' => l10n.dashboardPeriod1Week,
      '1month' => l10n.dashboardPeriod1Month,
      '1year' => l10n.dashboardPeriod1Year,
      _ => l10n.dashboardPeriodAll,
    };
    return InkWell(
      onTap: () async {
        await ref.read(hapticsServiceProvider).selection();
        final result = await SettingsPickerSheet.show<String>(
          context: context,
          title: l10n.dashboardPeriodTitle,
          options: options,
          currentValue: _usagePeriodKey,
          isSelected: (a, b) => a == b,
        );
        if (mounted && result != null) setState(() => _usagePeriodKey = result);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow.withOpacity(0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outline.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Expanded(
                child: Text(displayLabel,
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(color: theme.colorScheme.onSurface))),
            Icon(Icons.keyboard_arrow_down_rounded,
                color: theme.colorScheme.onSurface.withOpacity(0.6), size: 24),
          ],
        ),
      ),
    );
  }

  String _formatSpeed(double mbps) {
    if (mbps >= 1) return '${mbps.toStringAsFixed(2)} Mbps';
    final kbps = mbps * 1000;
    if (kbps >= 1) return '${kbps.toStringAsFixed(1)} Kbps';
    final bps = kbps * 1000;
    return '${bps.toStringAsFixed(0)} B/s';
  }

  String _formatMemory(int? mb) {
    if (mb == null) return '-- MB';
    return '$mb MB';
  }
}

class _DashboardHeaderIcon extends StatelessWidget {
  const _DashboardHeaderIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(11),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.72),
            color.withValues(alpha: 0.12),
          ],
        ),
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }
}

class _DashboardCard extends StatelessWidget {
  const _DashboardCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FrostedGlass(
      borderRadius: BorderRadius.circular(24),
      padding: const EdgeInsets.all(20),
      surface: GlassSurface.raised,
      child: child,
    );
  }
}

class _CompactStat extends StatelessWidget {
  const _CompactStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(
              value,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: color,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurface.withOpacity(0.6),
          ),
        ),
      ],
    );
  }
}

class _WebsiteTestCard extends StatelessWidget {
  const _WebsiteTestCard({
    required this.name,
    required this.id,
    this.result,
    required this.testing,
    required this.l10n,
    required this.onTest,
  });

  final String name;
  final String id;
  final LatencyResult? result;
  final bool testing;
  final AppLocalizations l10n;
  final VoidCallback onTest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 88,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_iconFor(id),
              size: 28,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.8)),
          const SizedBox(height: 8),
          Text(name,
              style: theme.textTheme.labelMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Container(
              height: 1,
              color: theme.colorScheme.outline.withValues(alpha: 0.2)),
          const SizedBox(height: 8),
          if (testing)
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: theme.colorScheme.primary),
            )
          else if (result != null)
            Text(
              _resultText(result!, l10n),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: _resultColor(result!),
              ),
            )
          else
            GestureDetector(
              onTap: onTest,
              child: Text(l10n.dashboardTest,
                  style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }

  Color _resultColor(LatencyResult result) {
    return switch (result) {
      LatencySuccess(:final ms) when ms <= 100 => HiVpnColors.success,
      LatencySuccess(:final ms) when ms <= 300 => HiVpnColors.warning,
      LatencySuccess(:final ms) when ms <= 1300 => HiVpnColors.error,
      LatencyTimeout() || LatencyError() => HiVpnColors.error,
      _ => HiVpnColors.error,
    };
  }

  String _resultText(LatencyResult r, AppLocalizations l10n) {
    return switch (r) {
      LatencySuccess(:final ms) => '${ms}ms',
      LatencyTimeout() || LatencyError() => l10n.dashboardTimeout,
    };
  }

  IconData _iconFor(String id) {
    switch (id) {
      case 'apple':
        return Icons.apple;
      case 'github':
        return Icons.code;
      case 'google':
        return Icons.g_mobiledata;
      case 'youtube':
        return Icons.play_circle_filled;
      case 'amazon':
        return Icons.shopping_bag;
      default:
        return Icons.language;
    }
  }
}

class _IpInfoRow extends StatelessWidget {
  const _IpInfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 48,
            child: Text('$label:',
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.65))),
          ),
          Expanded(
              child: Text(value,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

class _UsageTextRow extends StatelessWidget {
  const _UsageTextRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.8),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrafficSparkline extends StatelessWidget {
  const _TrafficSparkline({
    required this.uploadSamples,
    required this.downloadSamples,
    this.height = 48,
  });

  final List<double> uploadSamples;
  final List<double> downloadSamples;
  final double height;

  @override
  Widget build(BuildContext context) {
    const uploadColor = Color(0xFFF59E0B);
    const downloadColor = Color(0xFF38BDF8);
    final maxLen = uploadSamples.length > downloadSamples.length
        ? uploadSamples.length
        : downloadSamples.length;
    if (maxLen < 2) {
      return const SizedBox.shrink();
    }

    final rawMax = [
      ...uploadSamples,
      ...downloadSamples,
    ].reduce((a, b) => a > b ? a : b);
    // Round to a stable scale so a single sample cannot flatten every other
    // point, while keeping a quiet tunnel visibly near the baseline.
    final maxVal = rawMax <= 1
        ? 1.0
        : rawMax <= 10
            ? 10.0
            : rawMax <= 100
                ? 100.0
                : (rawMax / 100).ceil() * 100.0;

    final uploadSpots = uploadSamples.asMap().entries.map((e) {
      final normalized = maxVal > 0 ? (e.value / maxVal) : 0.0;
      final chartY = height - 4 - normalized * (height - 8);
      return FlSpot(e.key.toDouble(), chartY);
    }).toList();
    final downloadSpots = downloadSamples.asMap().entries.map((e) {
      final normalized = maxVal > 0 ? (e.value / maxVal) : 0.0;
      final chartY = height - 4 - normalized * (height - 8);
      return FlSpot(e.key.toDouble(), chartY);
    }).toList();

    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        minX: 0,
        maxX: (maxLen - 1).toDouble(),
        minY: 0,
        maxY: height,
        lineBarsData: [
          if (uploadSpots.length >= 2)
            LineChartBarData(
              spots: uploadSpots,
              isCurved: false,
              color: uploadColor,
              barWidth: 2,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(show: false),
            ),
          if (downloadSpots.length >= 2)
            LineChartBarData(
              spots: downloadSpots,
              isCurved: false,
              color: downloadColor,
              barWidth: 2,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(show: false),
            ),
        ],
      ),
      duration: const Duration(milliseconds: 220),
    );
  }
}
