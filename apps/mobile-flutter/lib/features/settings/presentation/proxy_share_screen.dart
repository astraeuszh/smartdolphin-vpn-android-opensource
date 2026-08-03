import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/ui/top_snack.dart';
import '../../../l10n/app_localizations.dart';
import '../../session/domain/session_controller.dart';
import '../../session/domain/session_status.dart';
import '../domain/advanced_settings_config.dart';
import '../domain/settings_controller.dart';

/// VPN 代理共享（前端流程）：主机展示二维码/连接信息；访客按「是否安装 App → 局域网 / P2P」决策树连接。
class ProxyShareScreen extends ConsumerStatefulWidget {
  const ProxyShareScreen({super.key});

  @override
  ConsumerState<ProxyShareScreen> createState() => _ProxyShareScreenState();
}

class _ProxyShareScreenState extends ConsumerState<ProxyShareScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  late String _shareKey;
  bool _hostLanScope = true;
  ProxyShareMode _protocol = ProxyShareMode.http;

  // Client wizard
  _ClientStep _clientStep = _ClientStep.hasAppQuestion;
  bool _p2pBusy = false;
  final _ipCtrl = TextEditingController();
  final _portCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _shareKey = _generateShareKey();
    final adv = ref.read(settingsControllerProvider).advanced;
    _protocol = adv.proxyShareMode == ProxyShareMode.socks5
        ? ProxyShareMode.socks5
        : ProxyShareMode.http;
    _hostLanScope = adv.proxyShareMode == ProxyShareMode.lan;
  }

  @override
  void dispose() {
    _tabs.dispose();
    _ipCtrl.dispose();
    _portCtrl.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }

  String _generateShareKey() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    return List.generate(12, (_) => chars[r.nextInt(chars.length)]).join();
  }

  int _portFor(ProxyShareMode mode) =>
      mode == ProxyShareMode.socks5 ? 1080 : 8080;

  String _mockHostIp() => '192.168.1.100';

  String _qrPayload(String ip, int port) {
    return jsonEncode({
      'v': 1,
      'type': 'smartdolphin_proxy_share',
      'host': ip,
      'port': port,
      'protocol': _protocol.name,
      'key': _shareKey,
      'lan': _hostLanScope,
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final advanced = ref.watch(settingsControllerProvider).advanced;
    final session = ref.watch(sessionControllerProvider);
    final vpnConnected = session.status == SessionStatus.connected;
    final ip = _mockHostIp();
    final port = _portFor(_protocol);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.proxyShareScreenTitle),
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: l10n.proxyShareHostTab),
            Tab(text: l10n.proxyShareClientTab),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _HostTab(
                  l10n: l10n,
                  theme: theme,
                  enabled: advanced.proxyShareEnabled,
                  vpnConnected: vpnConnected,
                  lanScope: _hostLanScope,
                  protocol: _protocol,
                  shareKey: _shareKey,
                  ip: ip,
                  port: port,
                  qrData: _qrPayload(ip, port),
                  onEnabledChanged: (v) async {
                    await ref
                        .read(settingsControllerProvider.notifier)
                        .setProxyShareEnabled(v);
                  },
                  onLanScopeChanged: (v) {
                    setState(() {
                      _hostLanScope = v;
                      ref
                          .read(settingsControllerProvider.notifier)
                          .setProxyShareMode(
                            v ? ProxyShareMode.lan : _protocol,
                          );
                    });
                  },
                  onProtocolChanged: (mode) {
                    setState(() {
                      _protocol = mode;
                      ref
                          .read(settingsControllerProvider.notifier)
                          .setProxyShareMode(
                            _hostLanScope ? ProxyShareMode.lan : mode,
                          );
                    });
                  },
                  onRegenerateKey: () =>
                      setState(() => _shareKey = _generateShareKey()),
                  onCopy: (text) => _copy(context, text, l10n.proxyShareCopied),
                ),
                _ClientTab(
                  l10n: l10n,
                  theme: theme,
                  step: _clientStep,
                  p2pBusy: _p2pBusy,
                  ipCtrl: _ipCtrl,
                  portCtrl: _portCtrl,
                  keyCtrl: _keyCtrl,
                  onHasApp: (yes) {
                    setState(() {
                      _clientStep = yes
                          ? _ClientStep.scanQr
                          : _ClientStep.sameLanQuestion;
                    });
                  },
                  onSameLan: (yes) {
                    setState(() {
                      _clientStep = yes
                          ? _ClientStep.manualConnect
                          : _ClientStep.p2pAttempt;
                      if (yes) {
                        _portCtrl.text = '${_portFor(_protocol)}';
                      }
                    });
                  },
                  onBack: () {
                    setState(() {
                      _clientStep = switch (_clientStep) {
                        _ClientStep.scanQr => _ClientStep.hasAppQuestion,
                        _ClientStep.sameLanQuestion =>
                          _ClientStep.hasAppQuestion,
                        _ClientStep.manualConnect =>
                          _ClientStep.sameLanQuestion,
                        _ClientStep.p2pAttempt ||
                        _ClientStep.p2pSuccess ||
                        _ClientStep.p2pFailed =>
                          _ClientStep.sameLanQuestion,
                        _ => _ClientStep.hasAppQuestion,
                      };
                      _p2pBusy = false;
                    });
                  },
                  onManualConnect: () {
                    showTopSnackBar(context, l10n.proxyShareManualConnectMock);
                  },
                  onStartP2p: () async {
                    setState(() {
                      _p2pBusy = true;
                      _clientStep = _ClientStep.p2pAttempt;
                    });
                    await Future<void>.delayed(const Duration(seconds: 3));
                    if (!mounted) return;
                    setState(() {
                      _p2pBusy = false;
                      _clientStep = _ClientStep.p2pFailed;
                    });
                  },
                  onReset: () {
                    setState(() {
                      _clientStep = _ClientStep.hasAppQuestion;
                      _p2pBusy = false;
                      _ipCtrl.clear();
                      _portCtrl.clear();
                      _keyCtrl.clear();
                    });
                  },
                ),
              ],
            ),
          ),
          _UnstableDisclaimer(text: l10n.featureUnstableDisclaimer),
        ],
      ),
    );
  }

  Future<void> _copy(BuildContext context, String text, String msg) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) showTopSnackBar(context, msg);
  }
}

enum _ClientStep {
  hasAppQuestion,
  scanQr,
  sameLanQuestion,
  manualConnect,
  p2pAttempt,
  p2pSuccess,
  p2pFailed,
}

class _HostTab extends StatelessWidget {
  const _HostTab({
    required this.l10n,
    required this.theme,
    required this.enabled,
    required this.vpnConnected,
    required this.lanScope,
    required this.protocol,
    required this.shareKey,
    required this.ip,
    required this.port,
    required this.qrData,
    required this.onEnabledChanged,
    required this.onLanScopeChanged,
    required this.onProtocolChanged,
    required this.onRegenerateKey,
    required this.onCopy,
  });

  final AppLocalizations l10n;
  final ThemeData theme;
  final bool enabled;
  final bool vpnConnected;
  final bool lanScope;
  final ProxyShareMode protocol;
  final String shareKey;
  final String ip;
  final int port;
  final String qrData;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<bool> onLanScopeChanged;
  final ValueChanged<ProxyShareMode> onProtocolChanged;
  final VoidCallback onRegenerateKey;
  final void Function(String text) onCopy;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        SwitchListTile.adaptive(
          value: enabled,
          onChanged: vpnConnected ? onEnabledChanged : null,
          title: Text(l10n.settingsProxyShare),
          subtitle: Text(
            vpnConnected
                ? l10n.proxyShareHostEnableHint
                : l10n.proxyShareVpnRequired,
          ),
        ),
        if (!vpnConnected)
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
            child: Text(
              l10n.proxyShareVpnRequired,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
            ),
          ),
        if (enabled && vpnConnected) ...[
          const SizedBox(height: 8),
          Text(l10n.proxyShareScopeTitle, style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: true, label: Text(l10n.proxyShareScopeLan)),
              ButtonSegment(
                  value: false, label: Text(l10n.proxyShareScopeRemote)),
            ],
            selected: {lanScope},
            onSelectionChanged: (s) => onLanScopeChanged(s.first),
          ),
          const SizedBox(height: 16),
          Text(l10n.proxyShareProtocolTitle, style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<ProxyShareMode>(
            segments: [
              ButtonSegment(
                value: ProxyShareMode.http,
                label: Text(l10n.settingsProxyShareHttp),
              ),
              ButtonSegment(
                value: ProxyShareMode.socks5,
                label: Text(l10n.settingsProxyShareSocks5),
              ),
            ],
            selected: {protocol},
            onSelectionChanged: (s) => onProtocolChanged(s.first),
          ),
          const SizedBox(height: 20),
          _InfoRow(
              label: l10n.proxyShareHostIp,
              value: ip,
              onCopy: () => onCopy(ip)),
          _InfoRow(
            label: l10n.proxyShareHostPort,
            value: '$port',
            onCopy: () => onCopy('$port'),
          ),
          _InfoRow(
            label: l10n.proxyShareHostKey,
            value: shareKey,
            onCopy: () => onCopy(shareKey),
            trailing: IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: l10n.proxyShareRegenerateKey,
              onPressed: onRegenerateKey,
            ),
          ),
          const SizedBox(height: 16),
          Text(l10n.proxyShareShowQr, style: theme.textTheme.titleSmall),
          const SizedBox(height: 12),
          Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: QrImageView(
                data: qrData,
                version: QrVersions.auto,
                size: 200,
                backgroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.proxyShareQrHint,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _ClientTab extends StatelessWidget {
  const _ClientTab({
    required this.l10n,
    required this.theme,
    required this.step,
    required this.p2pBusy,
    required this.ipCtrl,
    required this.portCtrl,
    required this.keyCtrl,
    required this.onHasApp,
    required this.onSameLan,
    required this.onBack,
    required this.onManualConnect,
    required this.onStartP2p,
    required this.onReset,
  });

  final AppLocalizations l10n;
  final ThemeData theme;
  final _ClientStep step;
  final bool p2pBusy;
  final TextEditingController ipCtrl;
  final TextEditingController portCtrl;
  final TextEditingController keyCtrl;
  final ValueChanged<bool> onHasApp;
  final ValueChanged<bool> onSameLan;
  final VoidCallback onBack;
  final VoidCallback onManualConnect;
  final VoidCallback onStartP2p;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Text(l10n.proxyShareClientIntro, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 16),
        switch (step) {
          _ClientStep.hasAppQuestion => _QuestionCard(
              question: l10n.proxyShareHasAppQuestion,
              yesLabel: l10n.proxyShareHasAppYes,
              noLabel: l10n.proxyShareHasAppNo,
              onYes: () => onHasApp(true),
              onNo: () => onHasApp(false),
            ),
          _ClientStep.scanQr => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.proxyShareScanQrTitle,
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(l10n.proxyShareScanQrHint,
                    style: theme.textTheme.bodyMedium),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () {
                    showTopSnackBar(context, l10n.proxyShareScanQrMock);
                  },
                  icon: const Icon(Icons.qr_code_scanner),
                  label: Text(l10n.authQrScanTitle),
                ),
                const SizedBox(height: 12),
                TextButton(onPressed: onBack, child: Text(l10n.commonNo)),
              ],
            ),
          _ClientStep.sameLanQuestion => _QuestionCard(
              question: l10n.proxyShareSameLanQuestion,
              yesLabel: l10n.proxyShareSameLanYes,
              noLabel: l10n.proxyShareSameLanNo,
              onYes: () => onSameLan(true),
              onNo: () => onSameLan(false),
            ),
          _ClientStep.manualConnect => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.proxyShareManualTitle,
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                TextField(
                  controller: ipCtrl,
                  decoration: InputDecoration(
                    labelText: l10n.proxyShareManualIpHint,
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: portCtrl,
                  decoration: InputDecoration(
                    labelText: l10n.proxyShareManualPortHint,
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: keyCtrl,
                  decoration: InputDecoration(
                    labelText: l10n.proxyShareManualKeyHint,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: onManualConnect,
                  child: Text(l10n.proxyShareConnect),
                ),
                TextButton(onPressed: onBack, child: Text(l10n.cancel)),
              ],
            ),
          _ClientStep.p2pAttempt => Column(
              children: [
                Text(l10n.proxyShareP2pTitle,
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: 16),
                if (p2pBusy) ...[
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(l10n.proxyShareP2pTrying, textAlign: TextAlign.center),
                ] else
                  FilledButton(
                      onPressed: onStartP2p,
                      child: Text(l10n.proxyShareP2pStart)),
                const SizedBox(height: 12),
                TextButton(onPressed: onBack, child: Text(l10n.cancel)),
              ],
            ),
          _ClientStep.p2pSuccess => _ResultCard(
              success: true,
              message: l10n.proxyShareP2pSuccess,
              onReset: onReset,
              l10n: l10n,
            ),
          _ClientStep.p2pFailed => _ResultCard(
              success: false,
              message: l10n.proxyShareP2pFailed,
              onReset: onReset,
              l10n: l10n,
            ),
        },
      ],
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    required this.question,
    required this.yesLabel,
    required this.noLabel,
    required this.onYes,
    required this.onNo,
  });

  final String question;
  final String yesLabel;
  final String noLabel;
  final VoidCallback onYes;
  final VoidCallback onNo;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(question, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            FilledButton(onPressed: onYes, child: Text(yesLabel)),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: onNo, child: Text(noLabel)),
          ],
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.success,
    required this.message,
    required this.onReset,
    required this.l10n,
  });

  final bool success;
  final String message;
  final VoidCallback onReset;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final color = success ? Colors.green : Theme.of(context).colorScheme.error;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(success ? Icons.check_circle_outline : Icons.error_outline,
                color: color, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            TextButton(
                onPressed: onReset, child: Text(l10n.proxyShareClientRestart)),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    required this.onCopy,
    this.trailing,
  });

  final String label;
  final String value;
  final VoidCallback onCopy;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: Theme.of(context).textTheme.bodySmall),
      subtitle:
          SelectableText(value, style: Theme.of(context).textTheme.titleMedium),
      trailing: trailing ??
          IconButton(
            icon: const Icon(Icons.copy_outlined),
            onPressed: onCopy,
          ),
    );
  }
}

class _UnstableDisclaimer extends StatelessWidget {
  const _UnstableDisclaimer({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Theme.of(context)
          .colorScheme
          .surfaceContainerHighest
          .withValues(alpha: 0.6),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}
