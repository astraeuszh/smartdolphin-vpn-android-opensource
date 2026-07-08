import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:app_settings/app_settings.dart';
import '../../../core/legal_urls.dart';
import '../../../core/platform/runtime_platform.dart';
import '../../../app/app.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/domain/auth_controller.dart';
import '../../auth/presentation/login_screen.dart';
import '../../usage/data_usage_controller.dart';
import '../../usage/data_usage_state.dart';
import '../domain/preferences_controller.dart';
import '../domain/preferences_state.dart';
import '../domain/settings_controller.dart';
import '../domain/advanced_settings_config.dart';
import '../domain/transport_profile.dart';
import '../domain/split_tunnel_config.dart';
import '../domain/traffic_mode.dart';
import '../domain/rule_draft.dart';
import '../domain/vpn_protocol.dart';
import '../../../platform/android/vpn_system_settings.dart';
import '../../smart_stable/smart_stable_notifier.dart';
import 'app_picker_screen.dart';
import 'account_settings_screen.dart';
import 'custom_dns_dialog.dart';
import 'settings_picker_sheet.dart';
import '../../../core/ui/sdrl_icon.dart';
import '../../../core/ui/top_snack.dart';
import '../../../services/haptics/haptics_service.dart';
import '../../../services/sdrl/sdrl_compiler.dart';
import '../../../services/sdrl/sdrl_rule_store.dart';
import '../../session/domain/session_controller.dart';
import '../../session/domain/session_status.dart';
import '../../../services/logging/vpn_logger.dart';
import '../../../widgets/legal_agreement_rich_text.dart';
import '../../../widgets/frosted_glass.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _checkingUpdate = false;

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
        _buildSmartStableSection(context),
        _sectionGap(),
        _buildLegalSection(context),
        _sectionGap(),
        _buildInfoFooter(context),
      ],
    );
  }

  Widget _buildInfoFooter(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final info = snapshot.data;
        final versionLabel = info?.version ?? '—';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.settingsAppInfo,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.settingsVersionLabel(versionLabel),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.72),
              ),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _checkingUpdate || info == null ? null : () => _checkForUpdate(context),
              child: Text(
                _checkingUpdate ? l10n.settingsCheckingUpdate : l10n.settingsCheckUpdate,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                  decoration: TextDecoration.underline,
                  decorationColor: theme.colorScheme.primary.withValues(alpha: 0.6),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _checkForUpdate(BuildContext context) async {
    if (_checkingUpdate) return;
    setState(() => _checkingUpdate = true);
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    setState(() => _checkingUpdate = false);
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final l10n = ctx.l10n;
        return AlertDialog(
          title: Text(l10n.settingsUpdateAvailableTitle),
          content: Text(l10n.settingsUpdateAvailableBody),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(l10n.commonNo)),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(l10n.commonYes)),
          ],
        );
      },
    );
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

  void _showInDevelopmentHint() {
    unawaited(ref.read(hapticsServiceProvider).selection());
    showTopSnackBar(context, context.l10n.settingsFeatureInDevelopment);
  }

  /// Grayed, non-functional picker tile for features not yet wired to the
  /// Dolphin-Core engine. Tapping explains it's still in development.
  Widget _lockedPickerTile(
    BuildContext context, {
    required String title,
    required String value,
  }) {
    final theme = Theme.of(context);
    return Opacity(
      opacity: 0.5,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: InkWell(
          onTap: _showInDevelopmentHint,
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
                Icon(Icons.lock_outline, size: 18, color: theme.colorScheme.onSurface.withValues(alpha: 0.55)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Grayed, non-functional switch row for features not yet wired to the engine.
  Widget _lockedSwitchTile(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    return Opacity(
      opacity: 0.5,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        onTap: _showInDevelopmentHint,
        leading: Icon(icon, color: theme.colorScheme.primary),
        title: Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withOpacity(0.65))),
        trailing: Icon(Icons.lock_outline, size: 18, color: theme.colorScheme.onSurface.withValues(alpha: 0.55)),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context, l10n.settingsSectionTrafficRouting),
        const SizedBox(height: 12),
        _buildPickerTile(
          context,
          title: l10n.settingsTrafficMode,
          value: _trafficModeLabel(routing.mode, l10n),
          onTap: () async {
            await ref.read(hapticsServiceProvider).selection();
            final result = await SettingsPickerSheet.show<String>(
              context: context,
              title: l10n.settingsTrafficMode,
              options: [
                SettingsPickerOption(
                  value: TrafficMode.global.name,
                  label:
                      '${l10n.settingsTrafficModeGlobal} — ${l10n.settingsTrafficModeGlobalSubtitle}',
                ),
                SettingsPickerOption(
                  value: TrafficMode.auto.name,
                  label:
                      '${l10n.settingsTrafficModeAuto} — ${l10n.settingsTrafficModeAutoHint}',
                ),
              ],
              currentValue: routing.mode == TrafficMode.auto
                  ? TrafficMode.auto.name
                  : TrafficMode.global.name,
              isSelected: (a, b) => a == b,
            );
            if (!mounted || result == null) return;
            final mode = result == TrafficMode.auto.name
                ? TrafficMode.auto
                : TrafficMode.global;
            await ref.read(settingsControllerProvider.notifier).setTrafficMode(mode);
            if (mounted &&
                ref.read(sessionControllerProvider).status ==
                    SessionStatus.connected) {
              showTopSnackBar(context, l10n.settingsRuleEditorReconnectHint);
            }
          },
        ),
        const SizedBox(height: 8),
        _lockedPickerTile(
          context,
          title: l10n.settingsTrafficModeRule,
          value: l10n.settingsFeatureInDevelopment,
        ),
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
            final mode = SplitTunnelMode.values.firstWhere(
              (m) => m.name == result,
              orElse: () => SplitTunnelMode.allTraffic,
            );
            await ref
                .read(settingsControllerProvider.notifier)
                .setAppSplitMode(mode);
            if (mode != SplitTunnelMode.allTraffic && mounted) {
              await Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const AppPickerScreen(),
                ),
              );
            }
            if (mounted &&
                ref.read(sessionControllerProvider).status ==
                    SessionStatus.connected) {
              showTopSnackBar(context, l10n.settingsRuleEditorReconnectHint);
            }
          },
        ),
        if (splitTunnel.mode != SplitTunnelMode.allTraffic) ...[
          const SizedBox(height: 8),
          _buildValueTile(
            context,
            l10n.settingsAppSelectApps,
            l10n.settingsAppSplitAppCount(splitTunnel.selectedPackages.length),
            onTap: () async {
              await ref.read(hapticsServiceProvider).selection();
              await Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const AppPickerScreen(),
                ),
              );
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
          value: protocol.dnsOption == VpnDnsOption.custom
              ? '${l10n.settingsDnsCustom} (${protocol.customDnsServers.isNotEmpty ? protocol.customDnsServers.first : ''})'
              : protocol.dnsOption.labelFor(l10n),
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
            final option = dnsOptionFromName(result);
            if (option == VpnDnsOption.custom) {
              final ip = await showCustomDnsDialog(context);
              if (!mounted || ip == null) return;
              await ref.read(settingsControllerProvider.notifier).setCustomDns(ip);
              return;
            }
            await ref.read(settingsControllerProvider.notifier).setDnsOption(option);
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
        _lockedSwitchTile(
          context,
          title: l10n.settingsBlockLocalDns,
          subtitle: l10n.settingsBlockLocalDnsSubtitle,
          icon: Icons.block_outlined,
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
        // Android always tunnels via VpnService (TUN); the system-proxy mode
        // isn't applicable, so this row is locked.
        _lockedPickerTile(
          context,
          title: l10n.settingsTunnelMode,
          value: l10n.settingsTunnelModeTun,
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
            final mode = KillSwitchMode.values.firstWhere(
              (m) => m.name == result,
              orElse: () => KillSwitchMode.off,
            );
            await ref.read(settingsControllerProvider.notifier).setKillSwitchMode(mode);
            if (!mounted) return;
            if (mode == KillSwitchMode.strict) {
              final alwaysOn = await isAlwaysOnVpnEnabled();
              if (!alwaysOn && mounted) {
                await _promptKillSwitchAlwaysOn(context);
              }
            }
          },
        ),
      ],
    );
  }

  Widget _buildSmartStableSection(BuildContext context) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsControllerProvider);
    final smartStable = ref.watch(smartStableProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context, l10n.smartStableTitle),
        const SizedBox(height: 12),
        _buildSwitchTile(
          context,
          value: smartStable.tuningEnabled,
          title: l10n.settingsSmartStableToggle,
          subtitle: l10n.settingsSmartStableToggleSubtitle,
          icon: Icons.speed_rounded,
          onChanged: (v) {
            unawaited(() async {
              await ref.read(hapticsServiceProvider).selection();
              final notifier = ref.read(smartStableProvider.notifier);
              if (v) {
                notifier.enableTuning();
              } else {
                notifier.disableTuning();
              }
              if (mounted &&
                  ref.read(sessionControllerProvider).status ==
                      SessionStatus.connected) {
                showTopSnackBar(context, l10n.settingsRuleEditorReconnectHint);
              }
            }());
          },
        ),
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
        _buildSwitchTile(
          context,
          value: settings.logConfig.enabled,
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
        if (settings.logConfig.enabled) ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.primary),
            title: Text(l10n.settingsClearLogs),
            subtitle: Text(l10n.settingsClearLogsSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await ref.read(hapticsServiceProvider).selection();
              await ref.read(vpnLoggerProvider).clearUserLogs();
              if (mounted) {
                showTopSnackBar(context, l10n.settingsClearLogsDone);
              }
            },
          ),
          _buildLogPathTile(context),
        ],
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
          showTopSnackBar(context, context.l10n.settingsLogPathOpened);
        }
      } on PlatformException catch (e) {
        if (mounted) {
          showTopSnackBar(context, e.message ?? context.l10n.settingsLogPathCopied);
        }
      }
    }
  }

  Future<void> _copyLogPathAndNotify(String path) async {
    try {
      await Clipboard.setData(ClipboardData(text: path));
      if (mounted) {
        showTopSnackBar(context, context.l10n.settingsLogPathCopied);
      }
    } catch (_) {
      if (mounted) {
        showTopSnackBar(context, path);
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
          final displayPath =
              path.isEmpty ? l10n.settingsLogPathLoading : path;
          return FrostedGlass(
            borderRadius: BorderRadius.circular(16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            surface: GlassSurface.flat,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.folder_outlined,
                    color: theme.colorScheme.primary, size: 24),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.settingsLogPath,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      GestureDetector(
                        onLongPress: path.isNotEmpty
                            ? () async {
                                await ref
                                    .read(hapticsServiceProvider)
                                    .selection();
                                await _copyLogPathAndNotify(path);
                              }
                            : null,
                        child: Text(
                          displayPath,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withOpacity(0.7),
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
                        child: Icon(Icons.open_in_new,
                            size: 22, color: theme.colorScheme.primary),
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

  String _coreProtocolLabel(String p) => switch (p) {
        'hysteria2' => 'Hysteria2',
        'wireguard' => 'WireGuard',
        _ => 'Reality (VLESS)',
      };

  String _coreProtocolHint(String p) {
    final zh = Localizations.localeOf(context).languageCode.startsWith('zh');
    return switch (p) {
      'reality' => zh ? '（轻量稳定，日常推荐）' : ' (Lightweight, daily use)',
      'hysteria2' => zh ? '（弱网/高丢包更佳）' : ' (Weak network / lossy links)',
      'wireguard' => zh ? '（低延迟，适合游戏）' : ' (Low latency, gaming)',
      _ => '',
    };
  }

  String _trafficModeLabel(TrafficMode mode, AppLocalizations l10n) {
    return switch (mode) {
      TrafficMode.global => l10n.settingsTrafficModeGlobal,
      TrafficMode.auto => l10n.settingsTrafficModeAuto,
      TrafficMode.rule => l10n.settingsTrafficModeRule,
    };
  }

  Widget _buildProtocolSection(BuildContext context) {
    final l10n = context.l10n;
    final coreProtocol = ref.watch(preferencesControllerProvider).coreProtocol;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context, l10n.settingsSectionProtocol),
        const SizedBox(height: 12),
        _buildPickerTile(
          context,
          title: l10n.settingsTransportProtocol,
          value: '${_coreProtocolLabel(coreProtocol)}${_coreProtocolHint(coreProtocol)}',
          onTap: () async {
            await ref.read(hapticsServiceProvider).selection();
            final result = await SettingsPickerSheet.show<String>(
              context: context,
              title: l10n.settingsTransportProtocol,
              options: [
                SettingsPickerOption(
                  value: 'reality',
                  label: '${_coreProtocolLabel('reality')}${_coreProtocolHint('reality')}',
                ),
                SettingsPickerOption(
                  value: 'hysteria2',
                  label: '${_coreProtocolLabel('hysteria2')}${_coreProtocolHint('hysteria2')}',
                ),
                SettingsPickerOption(
                  value: 'wireguard',
                  label: '${_coreProtocolLabel('wireguard')}${_coreProtocolHint('wireguard')}',
                ),
              ],
              currentValue: coreProtocol,
              isSelected: (a, b) => a == b,
            );
            if (!mounted || result == null) return;
            await ref.read(preferencesControllerProvider.notifier).setCoreProtocol(result);
            if (mounted &&
                ref.read(sessionControllerProvider).status ==
                    SessionStatus.connected) {
              showTopSnackBar(context, l10n.settingsRuleEditorReconnectHint);
            }
          },
        ),
      ],
    );
  }

  Widget _buildProxyShareSection(BuildContext context) {
    final l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context, l10n.settingsSectionProxyShare),
        const SizedBox(height: 12),
        // VPN sharing (proxy share) stays locked / in-development per product
        // decision: the host/guest P2P sharing flow is not production-ready, so
        // it is shown grayed instead of exposing the half-built screen.
        _lockedPickerTile(
          context,
          title: l10n.settingsProxyShare,
          value: l10n.statusDisconnected,
        ),
      ],
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
    final locale = Localizations.localeOf(context);
    if (locale.languageCode == 'zh') {
      return protocol.labelZh();
    }
    return protocol.labelEn();
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
              child: Text(
                usage.hasLimit ? l10n.settingsUsageLimit : l10n.settingsRechargeTraffic,
              ),
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
              Navigator.of(context).push<void>(
                PageRouteBuilder<void>(
                  opaque: true,
                  pageBuilder: (_, __, ___) => const AccountSettingsScreen(),
                  transitionsBuilder: (_, animation, __, child) =>
                      FadeTransition(opacity: animation, child: child),
                  transitionDuration: const Duration(milliseconds: 200),
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
          if (auth.status == AuthStatus.banned)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                auth.message ?? l10n.authAccountBanned,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildLanguageSection(BuildContext context, PreferencesState preferences) {
    final l10n = context.l10n;
    final locales = AppLocalizations.supportedLocales;
    final langOptions = locales
        .map(
          (locale) => SettingsPickerOption<String>(
            value: localeToTag(locale),
            label: AppLocalizations.localeDisplayNameWithCoverage(locale),
          ),
        )
        .toList();
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
              isSelected: (a, b) => a == b,
            );
            if (!mounted || result == null) return;
            await ref.read(preferencesControllerProvider.notifier).setLocale(result);
          },
        ),
      ],
    );
  }

  String _languageDisplayValue(String? code, AppLocalizations l10n) {
    final locale = parseLocaleFromTag(code ?? PreferencesState.defaultLocaleCode);
    return AppLocalizations.localeDisplayNameWithCoverage(locale);
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

  Future<void> _promptKillSwitchAlwaysOn(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final l10n = ctx.l10n;
        return AlertDialog(
          title: Text(l10n.settingsKillSwitchPromptTitle),
          content: Text(l10n.settingsKillSwitchPromptBody),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(l10n.commonLater)),
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                AppSettings.openAppSettings(type: AppSettingsType.vpn);
              },
              child: Text(l10n.settingsOpenVpnSettings),
            ),
          ],
        );
      },
    );
  }

  Future<_LimitDialogResult?> _showLimitDialog(BuildContext context, int? currentLimit) async {
    final l10n = context.l10n;
    final serverMax = _serverMaxLimitBytes();
    final maxGb = serverMax != null
        ? serverMax / (1024 * 1024 * 1024)
        : 10000.0;
    final minGb = 1.0;
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
                    helperText: l10n.settingsLimitHelper,
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
                    if (parsed < minGb) {
                      return l10n.settingsLimitErrorMinMb;
                    }
                    final bytes = (parsed * 1024 * 1024 * 1024).round();
                    if (serverMax != null && bytes > serverMax) {
                      return l10n.settingsLimitErrorExceedsServer;
                    }
                    if (serverMax == null && parsed > maxGb) {
                      return l10n.settingsLimitErrorExceedsMax;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: Text(l10n.close),
                      ),
                    ),
                    if (currentLimit != null) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(ctx).pop(const _LimitDialogResult.clear()),
                          child: Text(l10n.settingsRemoveLimit),
                        ),
                      ),
                    ],
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          if (formKey.currentState?.validate() ?? false) {
                            final parsed = double.parse(controller.text.trim());
                            final bytes = (parsed * 1024 * 1024 * 1024).round();
                            Navigator.of(ctx).pop(_LimitDialogResult(bytes));
                          }
                        },
                        child: Text(l10n.ok),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
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
    showTopSnackBar(context, l10n.snackbarLimitSaved);
  }

  Future<void> _handleResetUsage() async {
    await ref.read(hapticsServiceProvider).selection();
    await ref.read(dataUsageControllerProvider.notifier).resetUsage();
    if (!mounted) return;
    final l10n = context.l10n;
    showTopSnackBar(context, l10n.snackbarTrafficReset);
  }

  Future<bool> _confirmDiscardUnsavedRules(BuildContext context) async {
    final l10n = context.l10n;
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.settingsRuleEditorUnsavedTitle),
        content: Text(l10n.settingsRuleEditorUnsavedBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.settingsRuleEditorUnsavedStay),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.settingsRuleEditorUnsavedDiscard),
          ),
        ],
      ),
    );
    if (discard == true) {
      await ref.read(settingsControllerProvider.notifier).discardUnsavedRules();
    }
    return discard ?? false;
  }

  Future<void> _pickSavedRule(BuildContext context) async {
    final l10n = context.l10n;
    final saved = await SdrlRuleStore.listSavedRules();
    if (!mounted) return;
    if (saved.isEmpty) {
      showTopSnackBar(context, l10n.settingsRulePickerEmpty);
      return;
    }
    final picked = await SettingsPickerSheet.show<String>(
      context: context,
      title: l10n.settingsRulePicker,
      options: saved
          .map((r) => SettingsPickerOption(value: r.name, label: r.name))
          .toList(),
      currentValue: ref.read(settingsControllerProvider).routing.ruleDb.savedRuleName,
      isSelected: (a, b) => a == b,
    );
    if (!mounted || picked == null) return;
    final source = await SdrlRuleStore.loadNamedSource(picked);
    if (source == null || !mounted) return;
    final compiled = await SdrlCompiler.compile(source);
    if (!compiled.ok || !mounted) {
      showTopSnackBar(
        context,
        compiled.errors.isNotEmpty
            ? compiled.firstErrorMessage
            : l10n.settingsRuleEditorCompileErrorHint,
      );
      return;
    }
    await SdrlRuleStore.activateNamedRule(picked);
    await SdrlCompiler.persistResult(compiled, source);
    final connected =
        ref.read(sessionControllerProvider).status == SessionStatus.connected;
    await ref.read(settingsControllerProvider.notifier).saveCompiledCustomRules(
          text: source,
          sourceHash: compiled.sourceHash,
          savedRuleName: SdrlRuleStore.sanitizeFileName(picked),
          pendingReconnect: connected,
        );
    if (mounted) setState(() {});
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

class _RuleEditorHint extends ConsumerWidget {
  const _RuleEditorHint({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localeTag = ref.watch(preferencesControllerProvider).localeCode;
    final docUrl = LegalUrls.sdrlTutorialFor(localeTag);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontSize: 11,
      height: 1.35,
    );

    return Text.rich(
      TextSpan(
        style: muted,
        children: [
          TextSpan(text: l10n.settingsRuleEditorHintBody),
          TextSpan(
            text: l10n.settingsRuleEditorSdrlHintLink,
            style: muted?.copyWith(
              color: theme.colorScheme.primary,
              decoration: TextDecoration.underline,
            ),
            recognizer: TapGestureRecognizer()
              ..onTap = () => launchUrl(
                    Uri.parse(docUrl),
                    mode: LaunchMode.externalApplication,
                  ),
          ),
          TextSpan(text: l10n.settingsRuleEditorHintSuffix),
        ],
      ),
    );
  }
}
