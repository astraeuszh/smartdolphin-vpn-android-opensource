import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import '../../../core/platform/runtime_platform.dart';
import '../../../app/app.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/domain/auth_controller.dart';
import '../../auth/domain/traffic_policy.dart';
import '../../auth/presentation/login_screen.dart';
import '../../usage/data_usage_controller.dart';
import '../../usage/data_usage_state.dart';
import '../domain/preferences_controller.dart';
import '../domain/preferences_state.dart';
import '../domain/settings_controller.dart';
import '../domain/advanced_settings_config.dart';
import '../domain/split_tunnel_config.dart';
import '../domain/traffic_mode.dart';
import '../domain/vpn_protocol.dart';
import 'account_settings_screen.dart';
import 'rule_editor_screen.dart';
import 'settings_picker_sheet.dart';
import '../../../services/haptics/haptics_service.dart';
import '../../../services/logging/vpn_logger.dart';
import '../../../services/remote/console_endpoint.dart';
import '../../../widgets/legal_agreement_rich_text.dart';
import '../../../widgets/frosted_glass.dart';
import '../../../theme/colors.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String _logSizeLimit = '10';
  String _logCountLimit = '5';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final preferences = ref.watch(preferencesControllerProvider);
    final usage = ref.watch(dataUsageControllerProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 160),
      children: [
        Text(
          l10n.settingsTitle,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 24),
        _buildAccountSection(context),
        _sectionGap(),
        _buildConnectionSection(context, preferences),
        _sectionGap(),
        _buildTrafficRoutingSection(context),
        _sectionGap(),
        _buildDnsNetworkSection(context),
        _sectionGap(),
        _buildSecuritySection(context),
        _sectionGap(),
        _buildProtocolSection(context),
        _sectionGap(),
        _buildProxyShareSection(context),
        _sectionGap(),
        _buildUsageSection(context, usage),
        _sectionGap(),
        _buildLanguageSection(context, preferences),
        _sectionGap(),
        _buildDiagnosticsSection(context),
        _sectionGap(),
        _buildLegalSection(context),
        _sectionGap(),
        _buildInfoFooter(context),
      ],
    );
  }

  Widget _buildInfoFooter(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final auth = ref.watch(authControllerProvider);
    final policy = auth.session?.trafficPolicy ?? const TrafficPolicy();

    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final info = snapshot.data;
        final versionLabel = info == null
            ? '—'
            : '${info.version} (${info.buildNumber})';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '应用信息',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '版本 $versionLabel',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.72),
              ),
            ),
            if (policy.hasPolicy && policy.hasQuotaLimit) ...[
              const SizedBox(height: 8),
              Text(
                l10n.accountQuotaSummary(
                  policy.monthlyQuotaGb,
                  policy.monthlyUsedGb,
                  policy.quotaUtilization * 100,
                ),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.72),
                ),
              ),
            ],
            const SizedBox(height: 8),
            TextButton(
              onPressed: info == null ? null : () => _checkForUpdate(info),
              child: const Text('检查更新'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _checkForUpdate(PackageInfo info) async {
    await ref.read(hapticsServiceProvider).selection();
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final uri = Uri.parse('${ConsoleEndpoint.base}/api/client/update/check');
      final resp = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'version': info.version,
              'build': info.buildNumber,
              'platform': 'android',
            }),
          )
          .timeout(const Duration(seconds: 18));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        throw Exception((data['error'] as String?) ?? '检查失败');
      }
      if (!mounted) return;
      final force = data['force_update'] == true;
      final deprecated = data['deprecated'] == true;
      final minVersion = (data['min_version'] as String?) ?? '';
      String message;
      if (force) {
        message = '当前版本过低，请更新至 $minVersion 或更高版本';
      } else if (deprecated) {
        message = '当前版本已弃用，建议更新';
      } else {
        message = '当前已是最新版本';
      }
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('检查更新失败：$e')),
      );
    }
  }

  Widget _sectionGap() {
    return const Column(
      children: [
        SizedBox(height: 24),
        Divider(),
        SizedBox(height: 24),
      ],
    );
  }

  Widget _buildLegalSection(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context, l10n.settingsSectionLegal),
        const SizedBox(height: 12),
        LegalAgreementRichText(
          hintTemplate: l10n.settingsLegalAgreementHint,
          wrapInBookTitleMarks: true,
        ),
      ],
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    );
  }

  Widget _buildValueTile(BuildContext context, String title, String value, {VoidCallback? onTap}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: FrostedGlass(
          borderRadius: BorderRadius.circular(16),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          surface: GlassSurface.flat,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(value, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.7))),
                  ],
                ),
              ),
              Icon(Icons.keyboard_arrow_down_rounded, color: theme.colorScheme.onSurface.withValues(alpha: 0.6), size: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConnectionSection(BuildContext context, PreferencesState preferences) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsControllerProvider);
    final autoConnect = settings.autoConnect;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context, l10n.settingsConnection),
        const SizedBox(height: 12),
        if (isAndroidNative) ...[
          _buildSectionTitle(context, l10n.settingsSectionKeepAlive),
          const SizedBox(height: 8),
          _buildSwitchTile(
            context,
            value: autoConnect.connectOnLaunch,
            title: l10n.settingsAutoConnectOnLaunch,
            subtitle: l10n.settingsAutoConnectOnLaunchSubtitle,
            icon: Icons.power_settings_new,
            onChanged: (v) {
              unawaited(() async {
                await ref.read(hapticsServiceProvider).selection();
                await ref.read(settingsControllerProvider.notifier).setAutoConnect(onLaunch: v);
              }());
            },
          ),
          _buildSwitchTile(
            context,
            value: autoConnect.reconnectOnNetworkChange,
            title: l10n.settingsReconnectOnNetworkChange,
            subtitle: l10n.settingsReconnectOnNetworkChangeSubtitle,
            icon: Icons.wifi_find,
            onChanged: (v) {
              unawaited(() async {
                await ref.read(hapticsServiceProvider).selection();
                await ref.read(settingsControllerProvider.notifier).setAutoConnect(onNetworkChange: v);
              }());
            },
          ),
          _buildSwitchTile(
            context,
            value: autoConnect.connectOnBoot,
            title: l10n.settingsConnectOnBoot,
            subtitle: l10n.settingsConnectOnBootSubtitle,
            icon: Icons.restart_alt,
            onChanged: (v) {
              unawaited(() async {
                await ref.read(hapticsServiceProvider).selection();
                await ref.read(settingsControllerProvider.notifier).setAutoConnect(onBoot: v);
              }());
            },
          ),
          const SizedBox(height: 16),
        ],
        _buildSwitchTile(
          context,
          value: preferences.autoServerSwitch,
          title: l10n.settingsAutoSwitch,
          subtitle: l10n.settingsAutoSwitchSubtitle,
          icon: Icons.auto_mode,
          onChanged: (value) {
            unawaited(() async {
              await ref.read(hapticsServiceProvider).selection();
              await ref.read(preferencesControllerProvider.notifier).toggleAutoServerSwitch(value);
            }());
          },
        ),
        _buildSwitchTile(
          context,
          value: preferences.hapticsEnabled,
          title: l10n.settingsHaptics,
          subtitle: l10n.settingsHapticsSubtitle,
          icon: Icons.vibration,
          onChanged: (value) {
            unawaited(() async {
              await ref.read(hapticsServiceProvider).selection();
              await ref.read(preferencesControllerProvider.notifier).toggleHaptics(value);
            }());
          },
        ),
        _buildSwitchTile(
          context,
          value: settings.preciseSessionTimer,
          title: l10n.settingsPreciseSessionTimer,
          subtitle: l10n.settingsPreciseSessionTimerSubtitle,
          icon: Icons.timer_outlined,
          onChanged: (value) {
            unawaited(() async {
              await ref.read(hapticsServiceProvider).selection();
              await ref
                  .read(settingsControllerProvider.notifier)
                  .setPreciseSessionTimer(value);
            }());
          },
        ),
      ],
    );
  }

  Widget _buildTrafficRoutingSection(BuildContext context) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsControllerProvider);
    final routing = settings.routing;
    final splitTunnel = settings.splitTunnel;
    final ruleCount = routing.ruleDb.customRules
        .split(RegExp(r'\r?\n'))
        .where((s) => s.trim().isNotEmpty && !s.trim().startsWith('#'))
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context, l10n.settingsSectionTrafficRouting),
        const SizedBox(height: 12),
        _buildPickerTile(
          context,
          title: l10n.settingsTrafficMode,
          value: switch (routing.mode) {
            TrafficMode.global => l10n.settingsTrafficModeGlobal,
            TrafficMode.rule => l10n.settingsTrafficModeRule,
            TrafficMode.auto => l10n.settingsTrafficModeAuto,
          },
          onTap: () async {
            await ref.read(hapticsServiceProvider).selection();
            final result = await SettingsPickerSheet.show<String>(
              context: context,
              title: l10n.settingsTrafficMode,
              options: [
                SettingsPickerOption(value: TrafficMode.global.name, label: l10n.settingsTrafficModeGlobal),
                SettingsPickerOption(value: TrafficMode.auto.name, label: l10n.settingsTrafficModeAuto),
                SettingsPickerOption(value: TrafficMode.rule.name, label: l10n.settingsTrafficModeRule),
              ],
              currentValue: routing.mode.name,
              isSelected: (a, b) => a == b,
            );
            if (!mounted || result == null) return;
            await ref.read(settingsControllerProvider.notifier).setTrafficMode(
                  TrafficMode.values.firstWhere(
                    (m) => m.name == result,
                    orElse: () => TrafficMode.global,
                  ),
                );
          },
        ),
        if (routing.mode == TrafficMode.auto) ...[
          const SizedBox(height: 8),
          Text(
            l10n.settingsTrafficModeAutoHint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
        if (routing.mode == TrafficMode.rule) ...[
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.edit_note, color: Theme.of(context).colorScheme.primary),
            title: Text(l10n.settingsRuleEditor),
            subtitle: Text(
              routing.ruleDb.customRules.isEmpty
                  ? l10n.settingsRuleEditorEmptyHint
                  : l10n.settingsRuleEditorRuleCount(ruleCount),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await ref.read(hapticsServiceProvider).selection();
              if (!mounted) return;
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const RuleEditorScreen(),
                ),
              );
              if (mounted) setState(() {});
            },
          ),
        ],
        const SizedBox(height: 8),
        _buildPickerTile(
          context,
          title: l10n.settingsAppSplitMode,
          value: _appSplitModeLabel(splitTunnel.mode, l10n),
          onTap: () async {
            await ref.read(hapticsServiceProvider).selection();
            final result = await SettingsPickerSheet.show<String>(
              context: context,
              title: l10n.settingsAppSplitMode,
              options: [
                SettingsPickerOption(
                  value: SplitTunnelMode.allTraffic.name,
                  label: l10n.settingsAppSplitOff,
                ),
                SettingsPickerOption(
                  value: SplitTunnelMode.includeApps.name,
                  label: l10n.settingsAppSplitInclude,
                ),
                SettingsPickerOption(
                  value: SplitTunnelMode.excludeApps.name,
                  label: l10n.settingsAppSplitExclude,
                ),
              ],
              currentValue: splitTunnel.mode.name,
              isSelected: (a, b) => a == b,
            );
            if (!mounted || result == null) return;
            await ref.read(settingsControllerProvider.notifier).setAppSplitMode(
                  SplitTunnelMode.values.firstWhere(
                    (m) => m.name == result,
                    orElse: () => SplitTunnelMode.allTraffic,
                  ),
                );
          },
        ),
        if (splitTunnel.mode != SplitTunnelMode.allTraffic) ...[
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.apps_outlined, color: Theme.of(context).colorScheme.primary),
            title: Text(l10n.settingsAppSelectApps),
            subtitle: Text(
              splitTunnel.selectedPackages.isEmpty
                  ? l10n.settingsAppSelectAppsSubtitle
                  : l10n.settingsAppSplitAppCount(splitTunnel.selectedPackages.length),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              unawaited(() async {
                await ref.read(hapticsServiceProvider).selection();
                _showPendingSnackBar(context);
              }());
            },
          ),
        ],
        _buildSwitchTile(
          context,
          value: routing.autoRouteSystem,
          title: l10n.settingsAutoRoute,
          subtitle: l10n.settingsAutoRouteSubtitle,
          icon: Icons.route_outlined,
          onChanged: (v) {
            unawaited(() async {
              await ref.read(hapticsServiceProvider).selection();
              await ref.read(settingsControllerProvider.notifier).setAutoRouteSystem(v);
            }());
          },
        ),
        _buildSwitchTile(
          context,
          value: routing.bypassLan,
          title: l10n.settingsBypassLan,
          subtitle: l10n.settingsBypassLanSubtitle,
          icon: Icons.lan_outlined,
          onChanged: (v) {
            unawaited(() async {
              await ref.read(hapticsServiceProvider).selection();
              await ref.read(settingsControllerProvider.notifier).setBypassLan(v);
            }());
          },
        ),
      ],
    );
  }

  Widget _buildDnsNetworkSection(BuildContext context) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsControllerProvider);
    final protocol = settings.protocol;
    final advanced = settings.advanced;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context, l10n.settingsSectionDnsNetwork),
        const SizedBox(height: 12),
        _buildPickerTile(
          context,
          title: l10n.settingsDnsServer,
          value: protocol.dnsOption.labelFor(l10n),
          onTap: () async {
            await ref.read(hapticsServiceProvider).selection();
            final result = await SettingsPickerSheet.show<String>(
              context: context,
              title: l10n.settingsDnsServer,
              options: VpnDnsOption.values
                  .map((o) => SettingsPickerOption(value: o.name, label: o.labelFor(l10n)))
                  .toList(),
              currentValue: protocol.dnsOption.name,
              isSelected: (a, b) => a == b,
            );
            if (!mounted || result == null) return;
            await ref.read(settingsControllerProvider.notifier).setDnsOption(
                  dnsOptionFromName(result),
                );
          },
        ),
        _buildSwitchTile(
          context,
          value: advanced.forceDnsThroughTunnel,
          title: l10n.settingsForceDnsThroughTunnel,
          subtitle: l10n.settingsForceDnsThroughTunnelSubtitle,
          icon: Icons.dns_outlined,
          onChanged: (v) {
            unawaited(() async {
              await ref.read(hapticsServiceProvider).selection();
              await ref.read(settingsControllerProvider.notifier).setForceDnsThroughTunnel(v);
            }());
          },
        ),
        _buildSwitchTile(
          context,
          value: advanced.blockLocalDns,
          title: l10n.settingsBlockLocalDns,
          subtitle: l10n.settingsBlockLocalDnsSubtitle,
          icon: Icons.block_outlined,
          onChanged: (v) {
            unawaited(() async {
              await ref.read(hapticsServiceProvider).selection();
              await ref.read(settingsControllerProvider.notifier).setBlockLocalDns(v);
            }());
          },
        ),
        _buildSwitchTile(
          context,
          value: advanced.blockIpv6Dns,
          title: l10n.settingsBlockIpv6Dns,
          subtitle: l10n.settingsBlockIpv6DnsSubtitle,
          icon: Icons.filter_6_outlined,
          onChanged: (v) {
            unawaited(() async {
              await ref.read(hapticsServiceProvider).selection();
              await ref.read(settingsControllerProvider.notifier).setBlockIpv6Dns(v);
            }());
          },
        ),
        _buildSwitchTile(
          context,
          value: advanced.disableIpv6WhenConnected,
          title: l10n.settingsDisableIpv6,
          subtitle: l10n.settingsDisableIpv6Subtitle,
          icon: Icons.network_locked_outlined,
          onChanged: (v) {
            unawaited(() async {
              await ref.read(hapticsServiceProvider).selection();
              await ref.read(settingsControllerProvider.notifier).setDisableIpv6WhenConnected(v);
            }());
          },
        ),
        _buildPickerTile(
          context,
          title: l10n.settingsTunnelMode,
          value: _tunnelModeLabel(advanced.tunnelMode, l10n),
          onTap: () async {
            await ref.read(hapticsServiceProvider).selection();
            final result = await SettingsPickerSheet.show<String>(
              context: context,
              title: l10n.settingsTunnelMode,
              options: [
                SettingsPickerOption(
                  value: TunnelInterfaceMode.tun.name,
                  label: l10n.settingsTunnelModeTun,
                ),
                SettingsPickerOption(
                  value: TunnelInterfaceMode.systemProxy.name,
                  label: l10n.settingsTunnelModeSystemProxy,
                ),
              ],
              currentValue: advanced.tunnelMode.name,
              isSelected: (a, b) => a == b,
            );
            if (!mounted || result == null) return;
            await ref.read(settingsControllerProvider.notifier).setTunnelInterfaceMode(
                  TunnelInterfaceMode.values.firstWhere(
                    (m) => m.name == result,
                    orElse: () => TunnelInterfaceMode.tun,
                  ),
                );
          },
        ),
      ],
    );
  }

  Widget _buildSecuritySection(BuildContext context) {
    final l10n = context.l10n;
    final advanced = ref.watch(settingsControllerProvider).advanced;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context, l10n.settingsSectionSecurity),
        const SizedBox(height: 12),
        _buildPickerTile(
          context,
          title: l10n.settingsKillSwitch,
          value: _killSwitchLabel(advanced.killSwitchMode, l10n),
          onTap: () async {
            await ref.read(hapticsServiceProvider).selection();
            final result = await SettingsPickerSheet.show<String>(
              context: context,
              title: l10n.settingsKillSwitch,
              options: [
                SettingsPickerOption(
                  value: KillSwitchMode.off.name,
                  label: l10n.settingsKillSwitchOff,
                ),
                SettingsPickerOption(
                  value: KillSwitchMode.strict.name,
                  label: l10n.settingsKillSwitchStrict,
                ),
                SettingsPickerOption(
                  value: KillSwitchMode.smart.name,
                  label: l10n.settingsKillSwitchSmart,
                ),
              ],
              currentValue: advanced.killSwitchMode.name,
              isSelected: (a, b) => a == b,
            );
            if (!mounted || result == null) return;
            await ref.read(settingsControllerProvider.notifier).setKillSwitchMode(
                  KillSwitchMode.values.firstWhere(
                    (m) => m.name == result,
                    orElse: () => KillSwitchMode.off,
                  ),
                );
          },
        ),
      ],
    );
  }

  Widget _buildProtocolSection(BuildContext context) {
    final l10n = context.l10n;
    final advanced = ref.watch(settingsControllerProvider).advanced;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context, l10n.settingsSectionProtocol),
        const SizedBox(height: 12),
        _buildPickerTile(
          context,
          title: l10n.settingsTransportProtocol,
          value: _transportProtocolLabel(advanced.transportProtocol, l10n),
          onTap: () async {
            await ref.read(hapticsServiceProvider).selection();
            final result = await SettingsPickerSheet.show<String>(
              context: context,
              title: l10n.settingsTransportProtocol,
              options: TransportProtocol.values
                  .map(
                    (p) => SettingsPickerOption(
                      value: p.name,
                      label: _transportProtocolLabel(p, l10n),
                    ),
                  )
                  .toList(),
              currentValue: advanced.transportProtocol.name,
              isSelected: (a, b) => a == b,
            );
            if (!mounted || result == null) return;
            final protocol = TransportProtocol.values.firstWhere(
              (p) => p.name == result,
              orElse: () => TransportProtocol.openVpn,
            );
            await ref.read(settingsControllerProvider.notifier).setTransportProtocol(protocol);
            if (!mounted) return;
            if (!_isProtocolAvailable(protocol)) {
              _showPendingSnackBar(context);
            }
          },
        ),
      ],
    );
  }

  Widget _buildProxyShareSection(BuildContext context) {
    final l10n = context.l10n;
    final advanced = ref.watch(settingsControllerProvider).advanced;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context, l10n.settingsSectionProxyShare),
        const SizedBox(height: 12),
        _buildSwitchTile(
          context,
          value: advanced.proxyShareEnabled,
          title: l10n.settingsProxyShare,
          subtitle: l10n.settingsProxyShareSubtitle,
          icon: Icons.share_outlined,
          onChanged: (v) {
            unawaited(() async {
              await ref.read(hapticsServiceProvider).selection();
              await ref.read(settingsControllerProvider.notifier).setProxyShareEnabled(v);
              if (v && mounted) {
                _showPendingSnackBar(context);
              }
            }());
          },
        ),
        if (advanced.proxyShareEnabled) ...[
          const SizedBox(height: 8),
          _buildPickerTile(
            context,
            title: l10n.settingsProxyShareMode,
            value: _proxyShareModeLabel(advanced.proxyShareMode, l10n),
            onTap: () async {
              await ref.read(hapticsServiceProvider).selection();
              final result = await SettingsPickerSheet.show<String>(
                context: context,
                title: l10n.settingsProxyShareMode,
                options: [
                  SettingsPickerOption(
                    value: ProxyShareMode.http.name,
                    label: l10n.settingsProxyShareHttp,
                  ),
                  SettingsPickerOption(
                    value: ProxyShareMode.socks5.name,
                    label: l10n.settingsProxyShareSocks5,
                  ),
                  SettingsPickerOption(
                    value: ProxyShareMode.lan.name,
                    label: l10n.settingsProxyShareLan,
                  ),
                ],
                currentValue: advanced.proxyShareMode.name,
                isSelected: (a, b) => a == b,
              );
              if (!mounted || result == null) return;
              await ref.read(settingsControllerProvider.notifier).setProxyShareMode(
                    ProxyShareMode.values.firstWhere(
                      (m) => m.name == result,
                      orElse: () => ProxyShareMode.http,
                    ),
                  );
            },
          ),
        ],
      ],
    );
  }

  void _showPendingSnackBar(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.settingsSnackbarPending)),
    );
  }

  String _killSwitchLabel(KillSwitchMode mode, AppLocalizations l10n) {
    return switch (mode) {
      KillSwitchMode.off => l10n.settingsKillSwitchOff,
      KillSwitchMode.strict => l10n.settingsKillSwitchStrict,
      KillSwitchMode.smart => l10n.settingsKillSwitchSmart,
    };
  }

  String _appSplitModeLabel(SplitTunnelMode mode, AppLocalizations l10n) {
    return switch (mode) {
      SplitTunnelMode.allTraffic => l10n.settingsAppSplitOff,
      SplitTunnelMode.includeApps => l10n.settingsAppSplitInclude,
      SplitTunnelMode.excludeApps => l10n.settingsAppSplitExclude,
    };
  }

  String _tunnelModeLabel(TunnelInterfaceMode mode, AppLocalizations l10n) {
    return switch (mode) {
      TunnelInterfaceMode.tun => l10n.settingsTunnelModeTun,
      TunnelInterfaceMode.systemProxy => l10n.settingsTunnelModeSystemProxy,
    };
  }

  String _transportProtocolLabel(TransportProtocol protocol, AppLocalizations l10n) {
    final base = switch (protocol) {
      TransportProtocol.wireGuard => l10n.settingsProtocolWireGuard,
      TransportProtocol.openVpn => l10n.settingsProtocolOpenVpn,
      TransportProtocol.realityVless => l10n.settingsProtocolRealityVless,
      TransportProtocol.hysteria2 => l10n.settingsProtocolHysteria2,
      TransportProtocol.tuic => l10n.settingsProtocolTuic,
    };
    if (_isProtocolAvailable(protocol)) {
      return base;
    }
    return '$base (${l10n.settingsProtocolComingSoon})';
  }

  bool _isProtocolAvailable(TransportProtocol protocol) {
    return protocol == TransportProtocol.openVpn;
  }

  String _proxyShareModeLabel(ProxyShareMode mode, AppLocalizations l10n) {
    return switch (mode) {
      ProxyShareMode.http => l10n.settingsProxyShareHttp,
      ProxyShareMode.socks5 => l10n.settingsProxyShareSocks5,
      ProxyShareMode.lan => l10n.settingsProxyShareLan,
    };
  }

  Widget _buildDiagnosticsSection(BuildContext context) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsControllerProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context, l10n.settingsSectionDiagnostics),
        const SizedBox(height: 12),
        _buildSwitchTile(
          context,
          value: settings.networkQualityMonitoring,
          title: l10n.settingsNetworkQuality,
          subtitle: l10n.settingsNetworkQualitySubtitle,
          icon: Icons.network_check_outlined,
          onChanged: (v) {
            unawaited(() async {
              await ref.read(hapticsServiceProvider).selection();
              await ref.read(settingsControllerProvider.notifier).setNetworkQuality(v);
            }());
          },
        ),
        _buildSwitchTile(
          context,
          value: settings.batterySaverEnabled,
          title: l10n.settingsBatterySaver,
          subtitle: l10n.settingsBatterySaverSubtitle,
          icon: Icons.battery_saver_outlined,
          onChanged: (v) {
            unawaited(() async {
              await ref.read(hapticsServiceProvider).selection();
              await ref.read(settingsControllerProvider.notifier).setBatterySaver(v);
            }());
          },
        ),
        const SizedBox(height: 8),
        _buildLogsSection(context),
      ],
    );
  }

  Widget _buildUsageSection(BuildContext context, DataUsageState usage) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final usedGb = usage.usedBytes / (1024 * 1024 * 1024);
    final limitGb = usage.monthlyLimitBytes != null
        ? usage.monthlyLimitBytes! / (1024 * 1024 * 1024)
        : null;
    final summary = l10n.usageSummaryText(usedGb, limitGb);
    final progress = usage.hasLimit ? usage.utilization.clamp(0, 1).toDouble() : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context, l10n.settingsUsage),
        const SizedBox(height: 12),
        Text(
          l10n.settingsUsageSubtitle,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withOpacity(0.7),
          ),
        ),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: progress ?? 0,
            minHeight: 6,
            backgroundColor: theme.colorScheme.surface.withOpacity(0.3),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          summary,
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.tonal(
              onPressed: () => _handleLimitTap(context, usage.monthlyLimitBytes),
              child: Text(usage.hasLimit ? l10n.settingsUsageLimit : l10n.settingsSetLimit),
            ),
            OutlinedButton(
              onPressed: _handleResetUsage,
              child: Text(l10n.settingsResetUsage),
            ),
            if (usage.limitExceeded)
              Chip(
                backgroundColor: theme.colorScheme.error.withOpacity(0.12),
                label: Text(
                  '${((progress ?? 1) * 100).toStringAsFixed(0)}%',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildAccountSection(BuildContext context) {
    final l10n = context.l10n;
    final auth = ref.watch(authControllerProvider);
    final loggedIn = auth.status == AuthStatus.authenticated ||
        auth.status == AuthStatus.pending ||
        auth.status == AuthStatus.banned;
    final username = auth.session?.username ?? '';

    void openAuth({required bool register}) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => LoginScreen(startAsRegister: register),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context, l10n.settingsAccountTitle),
        const SizedBox(height: 12),
        if (!loggedIn) ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.login),
            title: Text(l10n.settingsLoginTitle),
            subtitle: Text(l10n.settingsLoginSubtitle),
            onTap: () => openAuth(register: false),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.person_add_outlined),
            title: Text(l10n.settingsRegisterTitle),
            subtitle: Text(l10n.settingsRegisterSubtitle),
            onTap: () => openAuth(register: true),
          ),
        ] else ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.manage_accounts_outlined),
            title: Text(l10n.settingsAccountManageTitle),
            subtitle: Text(username.isEmpty ? '—' : username),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const AccountSettingsScreen(),
                ),
              );
            },
          ),
          if (auth.status == AuthStatus.pending)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                auth.message ?? l10n.settingsPendingVpnApproval,
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
              ),
            ),
        ],
      ],
    );
  }

  static const _systemLocaleValue = '__system__';

  Widget _buildLanguageSection(BuildContext context, PreferencesState preferences) {
    final l10n = context.l10n;
    final locales = AppLocalizations.supportedLocales;
    final langOptions = [
      SettingsPickerOption<String>(value: _systemLocaleValue, label: l10n.settingsLanguageSystem),
      ...locales.map(
        (locale) => SettingsPickerOption<String>(
          value: localeToTag(locale),
          label: localeDisplayName(locale),
        ),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context, l10n.settingsSectionLanguage),
        const SizedBox(height: 12),
        _buildPickerTile(
          context,
          title: l10n.settingsLanguage,
          value: _languageDisplayValue(preferences.localeCode, l10n),
          onTap: () async {
            await ref.read(hapticsServiceProvider).selection();
            final result = await SettingsPickerSheet.show<String>(
              context: context,
              title: l10n.settingsLanguage,
              options: langOptions,
              currentValue: preferences.localeCode ?? PreferencesState.defaultLocaleCode,
              isSelected: (a, b) => (a ?? _systemLocaleValue) == b,
            );
            if (!mounted || result == null) return;
            await ref.read(preferencesControllerProvider.notifier).setLocale(
              result == _systemLocaleValue ? null : result,
            );
          },
        ),
      ],
    );
  }

  static const _vpnChannel = MethodChannel('com.example.vpn/VpnChannel');

  Future<void> _openLogDirectory(String path) async {
    if (path.isEmpty) return;
    if (isAndroidNative) {
      try {
        await _vpnChannel.invokeMethod('openLogDirectory', {'path': path});
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.settingsLogPathOpened)),
          );
        }
      } on PlatformException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.message ?? context.l10n.settingsLogPathCopied)),
          );
        }
      }
    }
  }

  Future<void> _copyLogPathAndNotify(String path) async {
    try {
      await Clipboard.setData(ClipboardData(text: path));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.settingsLogPathCopied)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(path)),
        );
      }
    }
  }

  Widget _buildLogPathTile(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final logger = ref.read(vpnLoggerProvider);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: FutureBuilder<String?>(
      future: logger.logDirectory,
      builder: (context, snapshot) {
        final path = snapshot.data ?? '';
        final displayPath = path.isEmpty ? l10n.settingsLogPathLoading : path;
        return FrostedGlass(
          borderRadius: BorderRadius.circular(16),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          surface: GlassSurface.flat,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.folder_outlined, color: theme.colorScheme.primary, size: 24),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.settingsLogPath,
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    GestureDetector(
                      onLongPress: path.isNotEmpty
                          ? () async {
                              await ref.read(hapticsServiceProvider).selection();
                              await _copyLogPathAndNotify(path);
                            }
                          : null,
                      child: Text(
                        displayPath,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.7),
                          fontFamily: 'monospace',
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              if (path.isNotEmpty)
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () async {
                      await ref.read(hapticsServiceProvider).selection();
                      await _openLogDirectory(path);
                    },
                    borderRadius: BorderRadius.circular(24),
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: Icon(Icons.open_in_new, size: 22, color: theme.colorScheme.primary),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
      ),
    );
  }

  Widget _buildLogsSection(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final logConfig = ref.watch(settingsControllerProvider).logConfig;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context, l10n.settingsSectionLogs),
        const SizedBox(height: 12),
        _buildSwitchTile(
          context,
          value: logConfig.enabled,
          title: l10n.settingsLogEnabled,
          subtitle: l10n.settingsLogEnabledSubtitle,
          icon: Icons.description_outlined,
          onChanged: (v) {
            unawaited(() async {
              await ref.read(hapticsServiceProvider).selection();
              await ref.read(settingsControllerProvider.notifier).setLogEnabled(v);
            }());
          },
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.delete_outline, color: theme.colorScheme.primary),
          title: Text(l10n.settingsClearLogs),
          subtitle: Text(l10n.settingsClearLogsSubtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            await ref.read(hapticsServiceProvider).selection();
            await ref.read(vpnLoggerProvider).clearLogs();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l10n.settingsClearLogsDone)),
              );
            }
          },
        ),
        const SizedBox(height: 8),
        _buildLogPathTile(context),
        _buildValueTile(context, l10n.settingsLogSizeLimit, '${logConfig.sizeLimitMb} MB', onTap: () async {
          await ref.read(hapticsServiceProvider).selection();
          final result = await SettingsPickerSheet.show<int>(
            context: context,
            title: l10n.settingsLogSizeLimit,
            options: [5, 10, 20, 50, 100].map((e) => SettingsPickerOption(value: e, label: '$e MB')).toList(),
            currentValue: logConfig.sizeLimitMb,
            isSelected: (a, b) => a == b,
          );
          if (!mounted || result == null) return;
          await ref.read(settingsControllerProvider.notifier).setLogSizeLimitMb(result);
        }),
        _buildValueTile(context, l10n.settingsLogCountLimit, '${logConfig.countLimit}', onTap: () async {
          await ref.read(hapticsServiceProvider).selection();
          final result = await SettingsPickerSheet.show<int>(
            context: context,
            title: l10n.settingsLogCountLimit,
            options: [3, 5, 7, 10, 20].map((e) => SettingsPickerOption(value: e, label: '$e')).toList(),
            currentValue: logConfig.countLimit,
            isSelected: (a, b) => a == b,
          );
          if (!mounted || result == null) return;
          await ref.read(settingsControllerProvider.notifier).setLogCountLimit(result);
        }),
      ],
    );
  }

  String _languageDisplayValue(String? code, AppLocalizations l10n) {
    final locale = parseLocaleFromTag(code ?? PreferencesState.defaultLocaleCode);
    return localeDisplayName(locale);
  }

  Widget _buildPickerTile(
    BuildContext context, {
    String? title,
    required String value,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: FrostedGlass(
          borderRadius: BorderRadius.circular(16),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          surface: GlassSurface.flat,
          child: Row(
          children: [
            Expanded(
              child: title != null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          value,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withOpacity(0.7),
                          ),
                        ),
                      ],
                    )
                  : Text(
                      value,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
            ),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              color: theme.colorScheme.onSurface.withOpacity(0.6),
              size: 24,
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildSwitchTile(
    BuildContext context, {
    required bool value,
    required String title,
    required String subtitle,
    required IconData icon,
    required ValueChanged<bool> onChanged,
  }) {
    final theme = Theme.of(context);
    return SwitchListTile.adaptive(
      value: value,
      onChanged: onChanged,
      activeColor: theme.colorScheme.primary,
      contentPadding: EdgeInsets.zero,
      title: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface.withOpacity(0.65),
        ),
      ),
      secondary: Icon(icon, color: theme.colorScheme.primary),
    );
  }

  int? _serverMaxLimitBytes() {
    return ref.read(authControllerProvider).session?.trafficPolicy.serverMaxLimitBytes;
  }

  Future<_LimitDialogResult?> _showLimitDialog(BuildContext context, int? currentLimit) async {
    final l10n = context.l10n;
    final serverMax = _serverMaxLimitBytes();
    final maxGb = serverMax != null
        ? serverMax / (1024 * 1024 * 1024)
        : 10000.0;
    final minMb = 1.0;
    final formKey = GlobalKey<FormState>();
    final controller = TextEditingController(
      text: currentLimit != null
          ? (currentLimit / (1024 * 1024 * 1024)).toStringAsFixed(2)
          : '',
    );
    try {
      final result = await showDialog<_LimitDialogResult?>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.settingsUsageLimit),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final gb in [1, 10, 100])
                      ActionChip(
                        label: Text('${gb} GB'),
                        onPressed: () {
                          Navigator.of(ctx).pop(
                            _LimitDialogResult(gb * 1024 * 1024 * 1024),
                          );
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: controller,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    hintText: l10n.settingsLimitHint,
                    helperText: serverMax != null
                        ? l10n.settingsLimitHelperServerMax(maxGb.toStringAsFixed(0))
                        : l10n.settingsLimitHelperDefault,
                  ),
                  validator: (value) {
                    final trimmed = value?.trim() ?? '';
                    if (trimmed.isEmpty) {
                      return l10n.settingsLimitErrorEmpty;
                    }
                    final parsed = double.tryParse(trimmed);
                    if (parsed == null || parsed <= 0) {
                      return l10n.settingsLimitErrorInvalid;
                    }
                    final bytes = (parsed * 1024 * 1024 * 1024).round();
                    if (bytes < (minMb * 1024 * 1024).round()) {
                      return l10n.settingsLimitErrorMinMb;
                    }
                    if (serverMax != null && bytes > serverMax) {
                      return l10n.settingsLimitErrorExceedsServer;
                    }
                    if (serverMax == null && parsed > maxGb) {
                      return l10n.settingsLimitErrorExceedsMax;
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            if (currentLimit != null)
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(const _LimitDialogResult.clear()),
                child: Text(l10n.settingsRemoveLimit),
              ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l10n.close),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) {
                  final parsed = double.parse(controller.text.trim());
                  final bytes = (parsed * 1024 * 1024 * 1024).round();
                  Navigator.of(ctx).pop(_LimitDialogResult(bytes));
                }
              },
              child: Text(l10n.ok),
            ),
          ],
        ),
      );
      return result;
    } finally {
      controller.dispose();
    }
  }

  Future<void> _handleLimitTap(BuildContext context, int? currentLimit) async {
    await ref.read(hapticsServiceProvider).selection();
    final result = await _showLimitDialog(context, currentLimit);
    if (!mounted || result == null) {
      return;
    }
    final notifier = ref.read(dataUsageControllerProvider.notifier);
    if (result.clear) {
      await notifier.setMonthlyLimit(null);
    } else if (result.limitBytes != null) {
      await notifier.setMonthlyLimit(result.limitBytes);
    }
    if (!mounted) return;
    final l10n = context.l10n;
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.snackbarLimitSaved)));
    }
  }

  Future<void> _handleResetUsage() async {
    await ref.read(hapticsServiceProvider).selection();
    await ref.read(dataUsageControllerProvider.notifier).resetUsage();
  }
}

class _LimitDialogResult {
  const _LimitDialogResult(this.limitBytes) : clear = false;
  const _LimitDialogResult.clear()
      : limitBytes = null,
        clear = true;

  final int? limitBytes;
  final bool clear;
}
