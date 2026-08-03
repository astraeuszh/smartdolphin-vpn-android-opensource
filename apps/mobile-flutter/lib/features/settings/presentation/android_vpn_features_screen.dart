import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/settings_controller.dart';
import '../domain/traffic_mode.dart';
import '../domain/vpn_protocol.dart';
import 'android_vpn_feature_strings.dart';

enum AndroidVpnFeatureCategory {
  connection,
  routing,
  securityDns,
  trafficProxy,
  tunnelAdvanced,
}

class AndroidVpnFeaturesScreen extends ConsumerStatefulWidget {
  const AndroidVpnFeaturesScreen({super.key, this.embeddedCategory});

  final AndroidVpnFeatureCategory? embeddedCategory;

  @override
  ConsumerState<AndroidVpnFeaturesScreen> createState() =>
      _AndroidVpnFeaturesScreenState();
}

class _AndroidVpnFeaturesScreenState
    extends ConsumerState<AndroidVpnFeaturesScreen> {
  static const _prefsPrefix = 'android_feature_demo_';
  final Map<String, bool> _switches = {};
  final Map<String, String> _values = {
    'protocol': 'WireGuard',
    'routing': '分流',
    'ruleInterval': '6h',
    'obfuscation': 'ShadowTLS',
    'socksPort': '1080',
    'httpPort': '8080',
    'controllerPort': '9090',
    'mtu': '1280',
  };

  @override
  void initState() {
    super.initState();
    unawaited(_restoreDemoValues());
  }

  Future<void> _restoreDemoValues() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in _demoSwitchKeys) {
      _switches[key] = prefs.getBool('$_prefsPrefix$key') ?? false;
    }
    for (final key in _values.keys.toList()) {
      _values[key] = prefs.getString('$_prefsPrefix$key') ?? _values[key]!;
    }
    if (mounted) setState(() {});
  }

  Future<void> _setDemoSwitch(String key, bool value) async {
    setState(() => _switches[key] = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_prefsPrefix$key', value);
    if (mounted) _showDemoNotice();
  }

  Future<void> _setDemoValue(String key, String value) async {
    setState(() => _values[key] = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefsPrefix$key', value);
    if (mounted) _showDemoNotice();
  }

  void _showDemoNotice() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
          SnackBar(content: Text(androidVpnText(context, 'demoNotice'))));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(settingsControllerProvider);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final category = widget.embeddedCategory;
    final sections = <Widget>[
      if (category == null) _statusBanner(dark),
      if (category == null || category == AndroidVpnFeatureCategory.routing)
        _section(androidVpnText(context, 'routingRules'), [
          _disabledActionTile(androidVpnText(context, 'domainRouting')),
          _disabledActionTile(androidVpnText(context, 'ipRouting')),
          _disabledActionTile(androidVpnText(context, 'ruleSubscription')),
        ]),
      if (category == null || category == AndroidVpnFeatureCategory.securityDns)
        _section(androidVpnText(context, 'securityDns'), [
          _disabledSwitchTile('DNS over HTTPS'),
          _disabledSwitchTile(androidVpnText(context, 'obfuscation')),
        ]),
      if (category == null ||
          category == AndroidVpnFeatureCategory.tunnelAdvanced)
        _section(androidVpnText(context, 'tunnelAdvanced'), [
          _disabledSwitchTile(androidVpnText(context, 'fakeIp')),
          _disabledSwitchTile(androidVpnText(context, 'controller')),
          _switchTile(
            androidVpnText(context, 'adDns'),
            state.protocol.dnsOption == VpnDnsOption.custom &&
                state.protocol.customDnsServers.contains('94.140.14.14'),
            (enabled) => enabled
                ? ref
                    .read(settingsControllerProvider.notifier)
                    .setCustomDns('94.140.14.14')
                : ref
                    .read(settingsControllerProvider.notifier)
                    .setDnsOption(VpnDnsOption.cloudflare),
            subtitle: 'AdGuard DNS · 94.140.14.14',
          ),
          _disabledActionTile(androidVpnText(context, 'ipLeak')),
          _disabledSwitchTile(androidVpnText(context, 'notification')),
        ]),
    ];
    if (category != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: sections,
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(androidVpnText(context, 'title'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        children: sections,
      ),
    );
  }

  Widget _statusBanner(bool dark) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF24292D) : const Color(0xFFF0F5F7),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(androidVpnText(context, 'status')),
      );

  Widget _section(String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: widget.embeddedCategory != null
            ? Column(children: _withDividers(children))
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                  child: Text(title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                Column(children: _withDividers(children)),
              ]),
      );

  List<Widget> _withDividers(List<Widget> items) {
    return items;
  }

  Widget _switchTile(String title, bool value, ValueChanged<bool> onChanged,
          {String? subtitle}) =>
      _featureRow(
        title: title,
        subtitle: subtitle,
        icon: _featureIcon(title),
        trailing: Switch.adaptive(value: value, onChanged: onChanged),
        onTap: () => onChanged(!value),
      );

  Widget _demoSwitch(String key, String title) =>
      _switchTile(title, _switches[key] ?? false, (v) => _setDemoSwitch(key, v),
          subtitle: androidVpnText(context, 'demo'));

  Widget _actionTile(String title, String value, VoidCallback onTap) =>
      _featureRow(
        title: title,
        subtitle: value,
        icon: _featureIcon(title),
        trailing: _valuePill(value, arrow: true),
        onTap: onTap,
      );

  Widget _disabledActionTile(String title, {String? subtitle}) => _featureRow(
        title: title,
        subtitle: subtitle ?? androidVpnText(context, 'demoNotice'),
        icon: _featureIcon(title),
        trailing: const Icon(Icons.chevron_right_rounded, size: 20),
        onTap: _showDemoNotice,
      );

  Widget _disabledSwitchTile(String title, {String? subtitle}) => _featureRow(
        title: title,
        subtitle: subtitle ?? androidVpnText(context, 'demoNotice'),
        icon: _featureIcon(title),
        trailing: Switch.adaptive(
          value: _switches[title] ?? false,
          onChanged: (value) => _setDemoSwitch(title, value),
        ),
        onTap: () => _setDemoSwitch(title, !(_switches[title] ?? false)),
      );

  Widget _featureRow({
    required String title,
    required IconData icon,
    required Widget trailing,
    required VoidCallback onTap,
    String? subtitle,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 21, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            trailing,
          ],
        ),
      ),
    );
  }

  Widget _valuePill(String value, {bool arrow = false}) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(maxWidth: 170),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Flexible(
          child: Text(value.isEmpty ? '—' : value,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall),
        ),
        if (arrow) ...[
          const SizedBox(width: 4),
          const Icon(Icons.expand_more_rounded, size: 17),
        ],
      ]),
    );
  }

  IconData _featureIcon(String title) {
    final value = title.toLowerCase();
    // Keep feature icons distinct even when the title is localized.
    if (value.contains('ad-block') ||
        value.contains('ad blocking') ||
        value.contains('广告') ||
        value.contains('광고') ||
        value.contains('広告')) {
      return Icons.ads_click_outlined;
    }
    if (value.contains('domain') ||
        value.contains('域名') ||
        value.contains('ドメイン')) {
      return Icons.language_outlined;
    }
    if (value.contains('ip range') ||
        value.contains('ip 段') ||
        value.contains('ip 대역')) {
      return Icons.account_tree_outlined;
    }
    if (value.contains('rule') ||
        value.contains('规则') ||
        value.contains('ルール')) {
      return Icons.rule_folder_outlined;
    }
    if (value.contains('dns over') ||
        value.contains('https') ||
        value.contains('doh')) {
      return Icons.lock_outline;
    }
    if (value.contains('dns')) return Icons.dns_outlined;
    if (value.contains('proxy') ||
        value.contains('socks') ||
        value.contains('http')) {
      return Icons.swap_horiz_rounded;
    }
    if (value.contains('routing') ||
        value.contains('分流') ||
        value.contains('라우팅')) {
      return Icons.alt_route_rounded;
    }
    if (value.contains('node') ||
        value.contains('latency') ||
        value.contains('节点')) {
      return Icons.speed_rounded;
    }
    if (value.contains('obfus') ||
        value.contains('混淆') ||
        value.contains('難読化')) {
      return Icons.blur_on_outlined;
    }
    if (value.contains('fake-ip') ||
        value.contains('fake ip') ||
        value.contains('fake-ip')) {
      return Icons.fingerprint_outlined;
    }
    if (value.contains('controller') ||
        value.contains('控制器') ||
        value.contains('컨트롤러')) {
      return Icons.developer_board_outlined;
    }
    if (value.contains('config') || value.contains('file'))
      return Icons.file_present_outlined;
    if (value.contains('port')) return Icons.settings_ethernet_rounded;
    if (value.contains('notification') ||
        value.contains('通知') ||
        value.contains('알림')) {
      return Icons.notifications_none_rounded;
    }
    if (value.contains('leak') ||
        value.contains('泄漏') ||
        value.contains('유출')) {
      return Icons.health_and_safety_outlined;
    }
    if (value.contains('traffic') ||
        value.contains('流量') ||
        value.contains('트래픽')) {
      return Icons.swap_vert_rounded;
    }
    return Icons.tune_outlined;
  }

  Widget _choiceTile(String title, String value, List<String> options,
          FutureOr<void> Function(String) onSelected) =>
      _actionTile(title, value, () async {
        final selected = await showModalBottomSheet<String>(
          context: context,
          showDragHandle: true,
          backgroundColor: Theme.of(context).colorScheme.surface,
          builder: (context) => SafeArea(
            child: ListView(shrinkWrap: true, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                child: Text(title,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
              for (final option in options)
                RadioListTile<String>(
                  value: option,
                  groupValue: value,
                  title: Text(option),
                  onChanged: (v) => Navigator.pop(context, v),
                ),
            ]),
          ),
        );
        if (selected != null) await onSelected(selected);
      });

  Widget _switchWithChoice(String key, String title, String value,
          List<String> options, FutureOr<void> Function(String) onSelected) =>
      Column(children: [
        _demoSwitch(key, title),
        if (_switches[key] ?? false)
          _choiceTile(
              androidVpnText(context, 'type'), value, options, onSelected),
      ]);

  Widget _switchWithText(String key, String title, String hint) =>
      Column(children: [
        _demoSwitch(key, title),
        if (_switches[key] ?? false)
          _textTile('URL', _values['${key}Url'] ?? '', hint: hint,
              onSaved: (v) async {
            if (!_validUrl(v)) {
              throw FormatException(androidVpnText(context, 'invalidHttps'));
            }
            await _setDemoValue('${key}Url', v.trim());
          }),
      ]);

  Widget _portTile(String switchKey, String title, String valueKey) =>
      Column(children: [
        _demoSwitch(switchKey, title),
        if (_switches[switchKey] ?? false)
          _numberTile(androidVpnText(context, 'port'), valueKey, 1, 65535),
      ]);

  Widget _numberTile(String title, String key, int min, int max,
          {FutureOr<void> Function(int)? onSaved}) =>
      _actionTile(title, _values[key] ?? '', () async {
        final result = await _showTextDialog(title, _values[key] ?? '',
            keyboardType: TextInputType.number,
            formatters: [FilteringTextInputFormatter.digitsOnly],
            validator: (text) {
          final value = int.tryParse(text);
          return value != null && value >= min && value <= max
              ? null
              : '${androidVpnText(context, 'range')} $min-$max';
        });
        if (result == null) return;
        await _setDemoValue(key, result);
        if (onSaved != null) await onSaved(int.parse(result));
      });

  Widget _textTile(String title, String value,
          {required String hint,
          required FutureOr<void> Function(String) onSaved}) =>
      _actionTile(title, value.isEmpty ? hint : value, () async {
        final result = await _showTextDialog(title, value, hint: hint);
        if (result == null) return;
        try {
          await onSaved(result);
        } on FormatException catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(e.message)));
          }
        }
      });

  Widget _urlTile(String title, {String? suffix}) =>
      _actionTile(title, suffix ?? 'URL 导入', () async {
        final result = await _showTextDialog(title, '', hint: 'https://');
        if (result == null) return;
        if (!_validUrl(result)) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(androidVpnText(context, 'invalidUrl'))));
          }
          return;
        }
        await _setDemoValue('${title.hashCode}', result.trim());
      });

  Widget _fileTile(String title, List<String> extensions) => _actionTile(title,
          '${androidVpnText(context, 'chooseFile')} (${extensions.join('/')})',
          () async {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: extensions,
          allowMultiple: false,
        );
        if (result == null || result.files.isEmpty) return;
        final extension = result.files.single.extension?.toLowerCase();
        if (extension == null || !extensions.contains(extension)) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(androidVpnText(context, 'invalidFile'))));
          }
          return;
        }
        await _setDemoValue('${title.hashCode}', result.files.single.name);
      });

  Future<String?> _showTextDialog(String title, String initial,
      {String? hint,
      TextInputType? keyboardType,
      List<TextInputFormatter>? formatters,
      String? Function(String)? validator}) async {
    final controller = TextEditingController(text: initial);
    String? error;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: keyboardType,
            inputFormatters: formatters,
            decoration: InputDecoration(hintText: hint, errorText: error),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(androidVpnText(context, 'cancel'))),
            FilledButton(
              onPressed: () {
                final text = controller.text.trim();
                final nextError = validator?.call(text);
                if (nextError != null) {
                  setDialogState(() => error = nextError);
                  return;
                }
                Navigator.pop(dialogContext, text);
              },
              child: Text(androidVpnText(context, 'save')),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    return result;
  }

  static bool _validUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    return uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty;
  }

  static bool _validIpList(String value) {
    final parts =
        value.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty);
    if (parts.isEmpty) return false;
    return parts.every((part) {
      final octets = part.split('.');
      return octets.length == 4 &&
          octets.every((o) {
            final n = int.tryParse(o);
            return n != null && n >= 0 && n <= 255;
          });
    });
  }

  static String _protocolLabel(VpnProtocol value) =>
      value == VpnProtocol.wireGuard ? 'WireGuard' : value.label;

  String _routingLabel(BuildContext context, TrafficMode value) =>
      switch (value) {
        TrafficMode.global => androidVpnText(context, 'global'),
        TrafficMode.rule ||
        TrafficMode.auto =>
          androidVpnText(context, 'rules'),
      };

  static const _demoSwitchKeys = [
    'doh',
    'obfuscationEnabled',
    'realtimeTraffic',
    'trafficStats',
    'socks',
    'http',
    'fakeIp',
    'controller',
    'adDns',
    'notificationControl',
  ];
}
