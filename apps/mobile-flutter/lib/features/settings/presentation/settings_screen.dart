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
import '../../auth/domain/account_session.dart';
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
import '../../../platform/android/audit_capture_channel.dart';
import '../../smart_stable/smart_stable_notifier.dart';
import 'app_picker_screen.dart';
import 'account_settings_screen.dart';
import 'android_vpn_features_screen.dart';
import 'custom_dns_dialog.dart';
import 'proxy_share_development_screen.dart';
import 'settings_picker_sheet.dart';
import '../../../core/ui/sdrl_icon.dart';
import '../../../core/ui/top_snack.dart';
import '../../../services/haptics/haptics_service.dart';
import '../../../services/sdrl/sdrl_compiler.dart';
import '../../../services/sdrl/sdrl_rule_store.dart';
import '../../session/domain/session_controller.dart';
import '../../session/domain/session_status.dart';
import '../../../services/logging/vpn_logger.dart';
import '../../../services/remote/console_audit.dart';
import '../../../services/remote/update_prompt.dart';
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
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 160),
      children: [
        Text(
          l10n.settingsTitle,
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.w700),
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
        _buildLanguageSection(context, preferences),
        _sectionGap(),
        _buildAppearanceSection(context),
        _sectionGap(),
        _buildSmartStableSection(context),
        _sectionGap(),
        _buildBatterySection(context),
        _sectionGap(),
        _buildLogSection(context),
        _sectionGap(),
        _buildUpdateSection(context),
        _sectionGap(),
        _buildLegalSection(context),
        _sectionGap(),
        _buildInfoFooter(context),
      ],
    );
  }

  Widget _buildAppearanceSection(BuildContext context) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsControllerProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context, l10n.settingsAppearance),
        const SizedBox(height: 12),
        _buildSwitchTile(
          context,
          value: settings.darkMode,
          title: l10n.settingsThemeDark,
          subtitle: l10n.settingsAppearanceSubtitle,
          icon: Icons.dark_mode_outlined,
          onChanged: (value) {
            unawaited(() async {
              await ref.read(hapticsServiceProvider).selection();
              await ref
                  .read(settingsControllerProvider.notifier)
                  .setDarkMode(value);
            }());
          },
        ),
        const SizedBox(height: 8),
        _buildAccentPicker(context, settings.accentSeed),
      ],
    );
  }

  Widget _buildAccentPicker(BuildContext context, String selected) {
    const accents = <String, Color>{
      'ocean': Color(0xFF1976D2),
      'aqua': Color(0xFF0891B2),
      'sunrise': Color(0xFFD97706),
      'forest': Color(0xFF16A34A),
      'lavender': Color(0xFF7C3AED),
    };
    final theme = Theme.of(context);
    return _settingsRow(
      theme,
      title: _settingsText(context, 'themeColor'),
      icon: Icons.palette_outlined,
      trailing: Wrap(
        spacing: 10,
        children: accents.entries.map((entry) {
          final active = entry.key == selected;
          return Semantics(
            button: true,
            selected: active,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => unawaited(ref
                  .read(settingsControllerProvider.notifier)
                  .setAccentSeed(entry.key)),
              child: Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: entry.value,
                  border: Border.all(
                    color: active
                        ? theme.colorScheme.onSurface
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildInfoFooter(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final info = snapshot.data;
        final versionLabel = info?.version.split('+').first ?? '-';

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
              onTap: _checkingUpdate || info == null
                  ? null
                  : () => _checkForUpdate(context),
              child: Text(
                _checkingUpdate
                    ? l10n.settingsCheckingUpdate
                    : l10n.settingsCheckUpdate,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                  decoration: TextDecoration.underline,
                  decorationColor:
                      theme.colorScheme.primary.withValues(alpha: 0.6),
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
    try {
      await checkAndPromptForUpdate(context);
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  Widget _sectionGap() {
    return const SizedBox(height: 32);
  }

  Widget _buildLegalSection(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context, l10n.settingsSectionLegal),
        const SizedBox(height: 12),
        Text.rich(
          TextSpan(
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
            children: [
              const TextSpan(text: '若想阅读我们的相关法律，请前往'),
              TextSpan(
                text: '我们的官方网站',
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
                recognizer: TapGestureRecognizer()
                  ..onTap = () => launchUrl(Uri.parse(LegalUrls.base),
                      mode: LaunchMode.externalApplication),
              ),
              const TextSpan(text: '查看法律。'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context)
          .textTheme
          .titleMedium
          ?.copyWith(fontWeight: FontWeight.w700),
    );
  }

  Widget _buildValueTile(BuildContext context, String title, String value,
      {VoidCallback? onTap}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: InkWell(
        onTap: onTap,
        child: _settingsRow(
          theme,
          title: title,
          icon: _settingIcon(title),
          trailing: _valuePill(theme, value),
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
          child: _settingsRow(theme,
              title: title,
              icon: _settingIcon(title),
              trailing: const Icon(Icons.lock_outline, size: 18)),
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
        title: Text(title,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.65))),
        trailing: Icon(Icons.lock_outline,
            size: 18,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.55)),
      ),
    );
  }

  Widget _buildConnectionSection(
      BuildContext context, PreferencesState preferences) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsControllerProvider);
    final autoConnect = settings.autoConnect;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context, l10n.settingsConnection),
        const SizedBox(height: 12),
        if (isAndroidNative) ...[
          _buildSwitchTile(
            context,
            value: autoConnect.connectOnLaunch,
            title: l10n.settingsAutoConnectOnLaunch,
            subtitle: l10n.settingsAutoConnectOnLaunchSubtitle,
            icon: Icons.power_settings_new,
            onChanged: (v) {
              unawaited(() async {
                await ref.read(hapticsServiceProvider).selection();
                await ref
                    .read(settingsControllerProvider.notifier)
                    .setAutoConnect(onLaunch: v);
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
                await ref
                    .read(settingsControllerProvider.notifier)
                    .setAutoConnect(onNetworkChange: v);
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
                await ref
                    .read(settingsControllerProvider.notifier)
                    .setAutoConnect(onBoot: v);
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
              await ref
                  .read(preferencesControllerProvider.notifier)
                  .toggleAutoServerSwitch(value);
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
              await ref
                  .read(preferencesControllerProvider.notifier)
                  .toggleHaptics(value);
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
                  label: l10n.settingsTrafficModeGlobal,
                ),
                SettingsPickerOption(
                  value: TrafficMode.auto.name,
                  label: l10n.settingsTrafficModeRule,
                ),
                SettingsPickerOption(
                  value: 'custom_rule_disabled',
                  label: l10n.settingsTrafficModeCustomRule,
                ),
              ],
              currentValue: routing.mode == TrafficMode.auto
                  ? TrafficMode.auto.name
                  : TrafficMode.global.name,
              isSelected: (a, b) => a == b,
            );
            if (!mounted || result == null) return;
            if (result == 'custom_rule_disabled') {
              _showInDevelopmentHint();
              return;
            }
            final mode = result == TrafficMode.auto.name
                ? TrafficMode.auto
                : TrafficMode.global;
            await ref
                .read(settingsControllerProvider.notifier)
                .setTrafficMode(mode);
            if (mounted &&
                ref.read(sessionControllerProvider).status ==
                    SessionStatus.connected) {
              showTopSnackBar(context, l10n.settingsRuleEditorReconnectHint);
            }
          },
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
              await ref
                  .read(settingsControllerProvider.notifier)
                  .setAutoRouteSystem(v);
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
              await ref
                  .read(settingsControllerProvider.notifier)
                  .setBypassLan(v);
            }());
          },
        ),
        const SizedBox(height: 12),
        const AndroidVpnFeaturesScreen(
          embeddedCategory: AndroidVpnFeatureCategory.routing,
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
                  .map((o) => SettingsPickerOption(
                      value: o.name, label: o.labelFor(l10n)))
                  .toList(),
              currentValue: protocol.dnsOption.name,
              isSelected: (a, b) => a == b,
            );
            if (!mounted || result == null) return;
            final option = dnsOptionFromName(result);
            if (option == VpnDnsOption.custom) {
              final ip = await showCustomDnsDialog(context);
              if (!mounted || ip == null) return;
              await ref
                  .read(settingsControllerProvider.notifier)
                  .setCustomDns(ip);
              return;
            }
            await ref
                .read(settingsControllerProvider.notifier)
                .setDnsOption(option);
          },
        ),
        _buildSwitchTile(
          context,
          value: advanced.forceDnsThroughTunnel,
          title: l10n.settingsForceDnsThroughTunnel,
          subtitle: l10n.settingsForceDnsThroughTunnelSubtitle,
          icon: Icons.policy_outlined,
          onChanged: (v) {
            unawaited(() async {
              await ref.read(hapticsServiceProvider).selection();
              await ref
                  .read(settingsControllerProvider.notifier)
                  .setForceDnsThroughTunnel(v);
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
              await ref
                  .read(settingsControllerProvider.notifier)
                  .setBlockLocalDns(v);
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
              await ref
                  .read(settingsControllerProvider.notifier)
                  .setBlockIpv6Dns(v);
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
              await ref
                  .read(settingsControllerProvider.notifier)
                  .setDisableIpv6WhenConnected(v);
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
            final mode = TunnelInterfaceMode.values.firstWhere(
              (item) => item.name == result,
              orElse: () => TunnelInterfaceMode.tun,
            );
            await ref
                .read(settingsControllerProvider.notifier)
                .setTunnelInterfaceMode(mode);
            if (mounted &&
                ref.read(sessionControllerProvider).status ==
                    SessionStatus.connected) {
              showTopSnackBar(context, l10n.settingsRuleEditorReconnectHint);
            }
          },
        ),
        const SizedBox(height: 12),
        const AndroidVpnFeaturesScreen(
          embeddedCategory: AndroidVpnFeatureCategory.securityDns,
        ),
      ],
    );
  }

  Widget _buildLegacySecuritySection(BuildContext context) {
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
                  label: '严格模式',
                ),
                SettingsPickerOption(
                  value: KillSwitchMode.smart.name,
                  label: '智能模式',
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
            await ref
                .read(settingsControllerProvider.notifier)
                .setKillSwitchMode(mode);
            if (!mounted) return;
            if (mode == KillSwitchMode.strict) {
              final ready = await isStrictKillSwitchReady();
              if (!ready && mounted) {
                await _promptKillSwitchAlwaysOn(context);
              }
            }
          },
        ),
      ],
    );
  }

  Widget _buildSecuritySection(BuildContext context) {
    final advanced = ref.watch(settingsControllerProvider).advanced;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context, _networkText(context, 'title')),
        const SizedBox(height: 12),
        _buildSwitchTile(
          context,
          value: advanced.killSwitchMode == KillSwitchMode.strict,
          title: _networkText(context, 'disconnect'),
          subtitle: _networkText(context, 'hint'),
          icon: Icons.shield_outlined,
          onChanged: (enabled) {
            unawaited(() async {
              await ref.read(hapticsServiceProvider).selection();
              await ref
                  .read(settingsControllerProvider.notifier)
                  .setKillSwitchMode(
                    enabled ? KillSwitchMode.strict : KillSwitchMode.off,
                  );
              if (!enabled || !mounted) return;
              if (!await isStrictKillSwitchReady() && mounted) {
                await _promptKillSwitchAlwaysOn(context);
              }
            }());
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
              await ref
                  .read(settingsControllerProvider.notifier)
                  .setNetworkQuality(v);
            }());
          },
        ),
      ],
    );
  }

  Widget _buildBatterySection(BuildContext context) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsControllerProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context, _settingsText(context, 'battery')),
        const SizedBox(height: 12),
        _buildSwitchTile(
          context,
          value: settings.batterySaverEnabled,
          title: l10n.settingsBatterySaver,
          subtitle: l10n.settingsBatterySaverSubtitle,
          icon: Icons.battery_saver_outlined,
          onChanged: (v) => unawaited(
              ref.read(settingsControllerProvider.notifier).setBatterySaver(v)),
        ),
      ],
    );
  }

  Widget _buildLogSection(BuildContext context) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsControllerProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context, _settingsText(context, 'logs')),
        const SizedBox(height: 12),
        _buildAuditPermissionTile(context),
        _buildSwitchTile(
          context,
          value: settings.logConfig.enabled,
          title: l10n.settingsLogEnabled,
          subtitle: l10n.settingsLogEnabledSubtitle,
          icon: Icons.description_outlined,
          onChanged: (v) {
            unawaited(() async {
              await ref.read(hapticsServiceProvider).selection();
              await ref
                  .read(settingsControllerProvider.notifier)
                  .setLogEnabled(v);
            }());
          },
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.delete_outline,
              color: Theme.of(context).colorScheme.primary),
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
    );
  }

  Widget _buildAuditPermissionTile(BuildContext context) {
    final theme = Theme.of(context);
    final session = ref.watch(authControllerProvider).session;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      enabled: session != null && session.sessionToken.trim().isNotEmpty,
      leading:
          Icon(Icons.privacy_tip_outlined, color: theme.colorScheme.primary),
      title: Text(_settingsText(context, 'logPermissionTitle')),
      subtitle: Text(_settingsText(context, 'logPermissionSubtitle')),
      trailing: const Icon(Icons.chevron_right),
      onTap: session == null || session.sessionToken.trim().isEmpty
          ? null
          : () => unawaited(_openAuditPermissionManagement(session)),
    );
  }

  Future<void> _openAuditPermissionManagement(AccountSession session) async {
    String current = 'basic';
    try {
      current = await ConsoleAudit().policy(session);
    } catch (_) {}
    if (!mounted) return;
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(_settingsText(context, 'logPermissionTitle')),
        children: [
          _auditOption(
              ctx, 'basic', current, 'auditBasicTitle', 'auditBasicSubtitle'),
          _auditOption(ctx, 'security', current, 'auditSecurityTitle',
              'auditSecuritySubtitle'),
          _auditOption(ctx, 'enhanced', current, 'auditEnhancedTitle',
              'auditEnhancedSubtitle'),
        ],
      ),
    );
    if (selected == null || selected == current || !mounted) return;
    if (selected != 'basic' && !await _confirmAuditConsent(selected)) return;
    try {
      final confirmed = await ConsoleAudit().updatePolicy(session, selected);
      await syncNativeAuditCapture(confirmed);
      if (mounted) {
        showTopSnackBar(context, _settingsText(context, 'auditSaved'));
      }
    } catch (_) {
      if (mounted) {
        showTopSnackBar(context, _settingsText(context, 'auditSaveFailed'),
            isError: true);
      }
    }
  }

  SimpleDialogOption _auditOption(BuildContext context, String mode,
      String current, String titleKey, String subtitleKey) {
    return SimpleDialogOption(
      onPressed: () => Navigator.of(context).pop(mode),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(_settingsText(context, titleKey)),
        subtitle: Text(_settingsText(context, subtitleKey)),
        trailing: current == mode ? const Icon(Icons.check) : null,
      ),
    );
  }

  Future<bool> _confirmAuditConsent(String mode) async {
    var accepted = false;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final titleKey = mode == 'security'
        ? 'auditSecurityConsentTitle'
        : 'auditEnhancedConsentTitle';
    final bodyKey = mode == 'security'
        ? 'auditSecurityConsentBody'
        : 'auditEnhancedConsentBody';
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => StatefulBuilder(
            builder: (dialogContext, setDialogState) => AlertDialog(
              title: Text(_settingsText(context, titleKey)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_settingsText(context, bodyKey)),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed: () => launchUrl(
                              Uri.parse(LegalUrls.privacyPolicyFor(locale)),
                              mode: LaunchMode.externalApplication),
                          child: Text(_settingsText(context, 'privacyPolicy')),
                        ),
                        TextButton(
                          onPressed: () => launchUrl(
                              Uri.parse(LegalUrls.userAgreementFor(locale)),
                              mode: LaunchMode.externalApplication),
                          child: Text(_settingsText(context, 'userAgreement')),
                        ),
                        TextButton(
                          onPressed: () => launchUrl(
                              Uri.parse(LegalUrls.serviceTermsFor(locale)),
                              mode: LaunchMode.externalApplication),
                          child: Text(_settingsText(context, 'serviceTerms')),
                        ),
                      ],
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: accepted,
                      onChanged: (value) =>
                          setDialogState(() => accepted = value == true),
                      title: Text(_settingsText(context, 'auditConsentCheck')),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: Text(_settingsText(context, 'cancel')),
                ),
                FilledButton(
                  onPressed: accepted
                      ? () => Navigator.of(dialogContext).pop(true)
                      : null,
                  child: Text(_settingsText(context, 'confirm')),
                ),
              ],
            ),
          ),
        ) ??
        false;
  }

  Widget _buildUpdateSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context, _settingsText(context, 'updates')),
        const SizedBox(height: 12),
        _buildSwitchTile(
          context,
          value: ref.watch(settingsControllerProvider).autoUpdateChecks,
          title: _settingsText(context, 'autoUpdate'),
          subtitle: _settingsText(context, 'autoUpdateHint'),
          icon: Icons.system_update_outlined,
          onChanged: (value) => unawaited(ref
              .read(settingsControllerProvider.notifier)
              .setAutoUpdateChecks(value)),
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
          showTopSnackBar(context, context.l10n.settingsLogPathOpened);
        }
      } on PlatformException catch (e) {
        if (mounted) {
          showTopSnackBar(
              context, e.message ?? context.l10n.settingsLogPathCopied);
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
          final displayPath = path.isEmpty ? l10n.settingsLogPathLoading : path;
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

  String _networkText(BuildContext context, String key) {
    const translations = <String, Map<String, String>>{
      'zh': {
        'title': '网络保护',
        'disconnect': '断开时阻止联网',
        'hint': 'VPN 意外断开时阻止网络访问。',
      },
      'zh-Hant': {
        'title': '網路保護',
        'disconnect': '中斷時封鎖網路',
        'hint': 'VPN 意外中斷時封鎖網路存取。',
      },
      'en': {
        'title': 'Network protection',
        'disconnect': 'Block connections when disconnected',
        'hint': 'Block network access if the VPN disconnects unexpectedly.',
      },
      'es': {
        'title': 'Proteccion de red',
        'disconnect': 'Bloquear conexiones al desconectar',
        'hint': 'Bloquea el acceso si la VPN se desconecta inesperadamente.',
      },
      'ja': {
        'title': 'ネットワーク保護',
        'disconnect': '切断時に通信をブロック',
        'hint': 'VPN が予期せず切断された場合に通信を遮断します。',
      },
    };
    return translations[_settingsLanguage(context)]?[key] ??
        translations['en']![key]!;
  }

  String _settingsText(BuildContext context, String key) {
    const translations = <String, Map<String, String>>{
      'zh': {
        'themeColor': '主题色',
        'battery': '电量',
        'logs': '日志',
        'updates': '更新设置',
        'autoUpdate': '自动检测更新',
        'autoUpdateHint': '在应用打开时检查已发布的更新。',
        'logPermissionTitle': '日志权限管理',
        'logPermissionSubtitle': '选择要同步到服务端的诊断范围。',
        'auditBasicTitle': '基础档',
        'auditBasicSubtitle': '连接时间、节点、协议和流量汇总。',
        'auditSecurityTitle': '安全诊断档',
        'auditSecuritySubtitle': '增加连接来源和设备诊断信息。',
        'auditEnhancedTitle': '增强诊断档',
        'auditEnhancedSubtitle': '增加网络路径与受控的 SNI 诊断信息。',
        'auditSecurityConsentTitle': '启用安全诊断',
        'auditSecurityConsentBody': '选择后，授权范围内的诊断数据会同步到服务端，用于改进连接质量。',
        'auditEnhancedConsentTitle': '启用增强诊断',
        'auditEnhancedConsentBody':
            '选择后，授权范围内的诊断数据会同步到服务端；不会采集 GPS、网页正文或完整数据包。',
        'auditConsentCheck': '我已阅读并同意上述数据范围',
        'privacyPolicy': '隐私政策',
        'userAgreement': '用户协议',
        'serviceTerms': '服务条款',
        'cancel': '取消',
        'confirm': '确认',
        'auditSaved': '日志权限已同步',
        'auditSaveFailed': '日志权限同步失败',
      },
      'zh-Hant': {
        'themeColor': '主題色',
        'battery': '電量',
        'logs': '日誌',
        'updates': '更新設定',
        'autoUpdate': '自動檢查更新',
        'autoUpdateHint': '開啟應用程式時檢查已發布的更新。',
        'logPermissionTitle': '日誌權限管理',
        'logPermissionSubtitle': '選擇要同步到伺服器的診斷範圍。',
        'auditBasicTitle': '基礎檔',
        'auditBasicSubtitle': '連線時間、節點、協定和流量摘要。',
        'auditSecurityTitle': '安全診斷檔',
        'auditSecuritySubtitle': '增加連線來源和裝置診斷資訊。',
        'auditEnhancedTitle': '增強診斷檔',
        'auditEnhancedSubtitle': '增加網路路徑與受控的 SNI 診斷資訊。',
        'auditSecurityConsentTitle': '啟用安全診斷',
        'auditSecurityConsentBody': '選擇後，授權範圍內的診斷資料會同步到伺服器，用於改善連線品質。',
        'auditEnhancedConsentTitle': '啟用增強診斷',
        'auditEnhancedConsentBody': '選擇後，授權範圍內的診斷資料會同步到伺服器；不會收集 GPS、網頁正文或完整封包。',
        'auditConsentCheck': '我已閱讀並同意上述資料範圍',
        'privacyPolicy': '隱私政策',
        'userAgreement': '使用者協議',
        'serviceTerms': '服務條款',
        'cancel': '取消',
        'confirm': '確認',
        'auditSaved': '日誌權限已同步',
        'auditSaveFailed': '日誌權限同步失敗',
      },
      'en': {
        'themeColor': 'Theme color',
        'battery': 'Battery',
        'logs': 'Logs',
        'updates': 'Updates',
        'autoUpdate': 'Automatically check for updates',
        'autoUpdateHint': 'Check for published updates when the app opens.',
        'logPermissionTitle': 'Log permissions',
        'logPermissionSubtitle':
            'Choose the diagnostic scope synced to the service.',
        'auditBasicTitle': 'Basic',
        'auditBasicSubtitle':
            'Connection time, node, protocol, and traffic totals.',
        'auditSecurityTitle': 'Security diagnostics',
        'auditSecuritySubtitle': 'Adds source and device diagnostic details.',
        'auditEnhancedTitle': 'Enhanced diagnostics',
        'auditEnhancedSubtitle':
            'Adds network path and controlled SNI diagnostics.',
        'auditSecurityConsentTitle': 'Enable security diagnostics',
        'auditSecurityConsentBody':
            'Authorized diagnostics will be synced to improve connection quality.',
        'auditEnhancedConsentTitle': 'Enable enhanced diagnostics',
        'auditEnhancedConsentBody':
            'Authorized diagnostics will be synced; GPS, page content, and full packets are excluded.',
        'auditConsentCheck': 'I have read and agree to this data scope',
        'privacyPolicy': 'Privacy policy',
        'userAgreement': 'User agreement',
        'serviceTerms': 'Service terms',
        'cancel': 'Cancel',
        'confirm': 'Confirm',
        'auditSaved': 'Log permissions synced',
        'auditSaveFailed': 'Could not sync log permissions',
      },
      'es': {
        'themeColor': 'Color del tema',
        'battery': 'Bateria',
        'logs': 'Registros',
        'updates': 'Actualizaciones',
        'autoUpdate': 'Buscar actualizaciones automaticamente',
        'autoUpdateHint': 'Busca actualizaciones publicadas al abrir la app.',
        'logPermissionTitle': 'Permisos de registros',
        'logPermissionSubtitle':
            'Elige el alcance de diagnostico que se sincroniza.',
        'auditBasicTitle': 'Basico',
        'auditBasicSubtitle': 'Hora, nodo, protocolo y totales de trafico.',
        'auditSecurityTitle': 'Diagnostico de seguridad',
        'auditSecuritySubtitle': 'Incluye datos de origen y del dispositivo.',
        'auditEnhancedTitle': 'Diagnostico avanzado',
        'auditEnhancedSubtitle':
            'Incluye ruta de red y diagnostico SNI controlado.',
        'auditSecurityConsentTitle': 'Activar diagnostico de seguridad',
        'auditSecurityConsentBody':
            'Los datos autorizados se sincronizaran para mejorar la conexion.',
        'auditEnhancedConsentTitle': 'Activar diagnostico avanzado',
        'auditEnhancedConsentBody':
            'Se sincronizan datos autorizados; se excluyen GPS, contenido y paquetes completos.',
        'auditConsentCheck': 'He leido y acepto este alcance de datos',
        'privacyPolicy': 'Politica de privacidad',
        'userAgreement': 'Acuerdo de usuario',
        'serviceTerms': 'Terminos del servicio',
        'cancel': 'Cancelar',
        'confirm': 'Confirmar',
        'auditSaved': 'Permisos sincronizados',
        'auditSaveFailed': 'No se pudieron sincronizar los permisos',
      },
      'ja': {
        'themeColor': 'テーマカラー',
        'battery': 'バッテリー',
        'logs': 'ログ',
        'updates': 'アップデート',
        'autoUpdate': '更新を自動確認',
        'autoUpdateHint': 'アプリを開いたときに公開済みの更新を確認します。',
        'logPermissionTitle': 'ログ権限',
        'logPermissionSubtitle': 'サービスへ同期する診断範囲を選択します。',
        'auditBasicTitle': '基本',
        'auditBasicSubtitle': '接続時刻、ノード、プロトコル、通信量。',
        'auditSecurityTitle': 'セキュリティ診断',
        'auditSecuritySubtitle': '接続元と端末の診断情報を追加します。',
        'auditEnhancedTitle': '拡張診断',
        'auditEnhancedSubtitle': 'ネットワーク経路と制御された SNI 診断を追加します。',
        'auditSecurityConsentTitle': 'セキュリティ診断を有効化',
        'auditSecurityConsentBody': '許可された診断データを接続品質の改善に利用し、サービスへ同期します。',
        'auditEnhancedConsentTitle': '拡張診断を有効化',
        'auditEnhancedConsentBody':
            '許可された診断データを同期します。GPS、ページ本文、完全なパケットは収集しません。',
        'auditConsentCheck': '上記のデータ範囲を読み、同意します',
        'privacyPolicy': 'プライバシーポリシー',
        'userAgreement': 'ユーザー規約',
        'serviceTerms': 'サービス規約',
        'cancel': 'キャンセル',
        'confirm': '確認',
        'auditSaved': 'ログ権限を同期しました',
        'auditSaveFailed': 'ログ権限を同期できませんでした',
      },
    };
    return translations[_settingsLanguage(context)]?[key] ??
        translations['en']![key]!;
  }

  String _settingsLanguage(BuildContext context) {
    final locale = Localizations.localeOf(context);
    if (locale.languageCode == 'zh' &&
        (locale.scriptCode == 'Hant' || locale.countryCode == 'TW')) {
      return 'zh-Hant';
    }
    return locale.languageCode;
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
      'hysteria2' => zh ? '（弱网和高丢包链路）' : ' (Weak network / lossy links)',
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

  Route<T> _instantRoute<T>(Widget page) {
    return PageRouteBuilder<T>(
      pageBuilder: (_, __, ___) => page,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
    );
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
          value:
              '${_coreProtocolLabel(coreProtocol)}${_coreProtocolHint(coreProtocol)}',
          onTap: () async {
            await ref.read(hapticsServiceProvider).selection();
            final result = await SettingsPickerSheet.show<String>(
              context: context,
              title: l10n.settingsTransportProtocol,
              options: [
                SettingsPickerOption(
                  value: 'reality',
                  label:
                      '${_coreProtocolLabel('reality')}${_coreProtocolHint('reality')}',
                ),
                SettingsPickerOption(
                  value: 'hysteria2',
                  label:
                      '${_coreProtocolLabel('hysteria2')}${_coreProtocolHint('hysteria2')}',
                ),
                SettingsPickerOption(
                  value: 'wireguard',
                  label:
                      '${_coreProtocolLabel('wireguard')}${_coreProtocolHint('wireguard')}',
                ),
              ],
              currentValue: coreProtocol,
              isSelected: (a, b) => a == b,
            );
            if (!mounted || result == null) return;
            await ref
                .read(preferencesControllerProvider.notifier)
                .setCoreProtocol(result);
            if (mounted &&
                ref.read(sessionControllerProvider).status ==
                    SessionStatus.connected) {
              showTopSnackBar(context, l10n.settingsRuleEditorReconnectHint);
            }
          },
        ),
        const SizedBox(height: 12),
        const AndroidVpnFeaturesScreen(
          embeddedCategory: AndroidVpnFeatureCategory.tunnelAdvanced,
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
        _buildPickerTile(
          context,
          title: l10n.settingsProxyShare,
          value: l10n.settingsFeatureInDevelopment,
          onTap: () async {
            await ref.read(hapticsServiceProvider).selection();
            if (!context.mounted) return;
            await Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const ProxyShareDevelopmentScreen(),
              ),
            );
          },
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

  String _transportProtocolLabel(
      TransportProtocol protocol, AppLocalizations l10n) {
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
    final progress =
        usage.hasLimit ? usage.utilization.clamp(0, 1).toDouble() : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context, l10n.settingsUsage),
        const SizedBox(height: 12),
        Text(
          l10n.settingsUsageTrackingNote,
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
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.tonal(
              onPressed: () =>
                  _handleLimitTap(context, usage.monthlyLimitBytes),
              child: Text(
                usage.hasLimit
                    ? l10n.settingsLimitActionChange
                    : l10n.settingsLimitActionSet,
              ),
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
            subtitle: Text(username.isEmpty ? '-' : username),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push<void>(
                _instantRoute<void>(const AccountSettingsScreen()),
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

  Widget _buildLanguageSection(
      BuildContext context, PreferencesState preferences) {
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
              currentValue:
                  preferences.localeCode ?? PreferencesState.defaultLocaleCode,
              isSelected: (a, b) => a == b,
            );
            if (!mounted || result == null) return;
            await ref
                .read(preferencesControllerProvider.notifier)
                .setLocale(result);
          },
        ),
      ],
    );
  }

  String _languageDisplayValue(String? code, AppLocalizations l10n) {
    final locale =
        parseLocaleFromTag(code ?? PreferencesState.defaultLocaleCode);
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
      padding: const EdgeInsets.only(bottom: 1),
      child: InkWell(
        onTap: onTap,
        child: _settingsRow(theme,
            title: title ?? value,
            icon: _settingIcon(title ?? value),
            trailing:
                _valuePill(theme, title == null ? '' : value, arrow: true)),
      ),
    );
  }

  Widget _settingsRow(ThemeData theme,
      {required String title,
      required IconData icon,
      required Widget trailing}) {
    return Container(
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Row(children: [
        Icon(icon, size: 21, color: theme.colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
            child: Text(title,
                style: theme.textTheme.bodyLarge
                    ?.copyWith(fontWeight: FontWeight.w600))),
        trailing,
      ]),
    );
  }

  Widget _valuePill(ThemeData theme, String value, {bool arrow = false}) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 180),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Flexible(
            child: Text(value.isEmpty ? '—' : value,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall)),
        if (arrow) ...[
          const SizedBox(width: 4),
          const Icon(Icons.expand_more_rounded, size: 17),
        ],
      ]),
    );
  }

  IconData _settingIcon(String title) {
    final value = title.toLowerCase();
    if (value.contains('select apps') ||
        value.contains('选择应用') ||
        value.contains('アプリを選択') ||
        value.contains('앱 선택')) {
      return Icons.checklist_outlined;
    }
    if (value.contains('traffic mode') ||
        value.contains('流量模式') ||
        value.contains('トラフィック') ||
        value.contains('트래픽 모드')) {
      return Icons.swap_vert_rounded;
    }
    if (value.contains('app split') ||
        value.contains('应用分流') ||
        value.contains('앱별 라우팅') ||
        value.contains('アプリ別')) {
      return Icons.apps_outlined;
    }
    if (value.contains('dns server') ||
        value.contains('自定义 dns') ||
        value.contains('dns 서버')) {
      return Icons.dns_outlined;
    }
    if (value.contains('force dns') || value.contains('强制 dns')) {
      return Icons.policy_outlined;
    }
    if (value.contains('tunnel') ||
        value.contains('隧道') ||
        value.contains('トンネル')) {
      return Icons.alt_route_outlined;
    }
    if (value.contains('kill switch') ||
        value.contains('断网') ||
        value.contains('network protection') ||
        value.contains('네트워크 보호')) {
      return Icons.health_and_safety_outlined;
    }
    if (value.contains('proxy share') ||
        value.contains('代理共享') ||
        value.contains('共有') ||
        value.contains('프록시 공유')) {
      return Icons.share_outlined;
    }
    if (value.contains('language') ||
        value.contains('语言') ||
        value.contains('言語')) {
      return Icons.translate_outlined;
    }
    if (value.contains('dns')) return Icons.dns_outlined;
    if (value.contains('protocol') || value.contains('协议'))
      return Icons.hub_outlined;
    if (value.contains('split') || value.contains('分流'))
      return Icons.alt_route_rounded;
    if (value.contains('language') || value.contains('语言'))
      return Icons.language_rounded;
    if (value.contains('theme') || value.contains('主题'))
      return Icons.dark_mode_outlined;
    if (value.contains('port') || value.contains('端口'))
      return Icons.settings_ethernet_rounded;
    return Icons.tune_outlined;
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
        style:
            theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
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
    return ref
        .read(authControllerProvider)
        .session
        ?.trafficPolicy
        .serverMaxLimitBytes;
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
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(l10n.commonLater)),
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

  Future<_LimitDialogResult?> _showLimitDialog(
      BuildContext context, int? currentLimit) async {
    final l10n = context.l10n;
    final serverMax = _serverMaxLimitBytes();
    final maxGb =
        serverMax != null ? serverMax / (1024 * 1024 * 1024) : 10000.0;
    final minGb = 0.01;
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
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    hintText: '0.01 - 10000',
                    helperText: l10n.settingsLimitUnitGb,
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
                      return l10n.settingsLimitServerThrottled;
                    }
                    if (serverMax == null && parsed > maxGb) {
                      return l10n.settingsLimitErrorExceedsMax;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: Text(l10n.commonClose),
                    ),
                    FilledButton(
                      onPressed: () {
                        if (formKey.currentState?.validate() ?? false) {
                          final parsed = double.parse(controller.text.trim());
                          final bytes = (parsed * 1024 * 1024 * 1024).round();
                          Navigator.of(ctx).pop(_LimitDialogResult(bytes));
                        }
                      },
                      child: Text(l10n.commonConfirm),
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
      currentValue:
          ref.read(settingsControllerProvider).routing.ruleDb.savedRuleName,
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
