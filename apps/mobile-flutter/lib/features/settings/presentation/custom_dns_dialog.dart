import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/ui/top_snack.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/network/dns_probe.dart';

/// 自定义 DNS：分四段数字输入，检测后返回 IP。
Future<String?> showCustomDnsDialog(BuildContext context) async {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => const _CustomDnsDialog(),
  );
}

class _CustomDnsDialog extends StatefulWidget {
  const _CustomDnsDialog();

  @override
  State<_CustomDnsDialog> createState() => _CustomDnsDialogState();
}

class _CustomDnsDialogState extends State<_CustomDnsDialog> {
  final _fields = List.generate(4, (_) => TextEditingController());
  final _nodes = List.generate(4, (_) => FocusNode());
  bool _checking = false;
  String _status = '';

  @override
  void dispose() {
    for (final c in _fields) {
      c.dispose();
    }
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  String? _assembledIp() {
    final parts = _fields.map((c) => c.text.trim()).toList();
    if (parts.any((p) => p.isEmpty)) return null;
    return parts.join('.');
  }

  Future<void> _confirm() async {
    final l10n = AppLocalizations.of(context);
    final ip = _assembledIp();
    if (ip == null || !DnsProbe.isValidIpv4(ip)) {
      setState(() => _status = l10n.dnsEnterFullIpv4);
      return;
    }
    setState(() {
      _checking = true;
      _status = l10n.dnsCheckingIpRange;
    });
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    setState(() => _status = l10n.dnsCheckingConnectivity);
    // Do not probe TCP/53 — many public DNS servers block it, and the probe
    // fails over mobile/VPN even when DoH through the tunnel would work fine.
    if (!mounted) return;
    Navigator.of(context).pop(ip);
    showTopSnackBar(context, l10n.dnsSetSuccess);
  }

  void _onChanged(int index, String value) {
    if (value.length > 3) {
      _fields[index].text = value.substring(0, 3);
      _fields[index].selection = TextSelection.collapsed(offset: 3);
    }
    final n = int.tryParse(_fields[index].text);
    if (n != null && n > 255) {
      _fields[index].text = '255';
    }
    if (_fields[index].text.length >= 3 && index < 3) {
      _nodes[index + 1].requestFocus();
    }
  }

  KeyEventResult _onKey(int index, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (index < 3) {
        _nodes[index + 1].requestFocus();
      } else {
        unawaited(_confirm());
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.backspace &&
        _fields[index].text.isEmpty &&
        index > 0) {
      _nodes[index - 1].requestFocus();
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.dnsTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.dnsHint),
          const SizedBox(height: 16),
          Row(
            children: [
              for (var i = 0; i < 4; i++) ...[
                if (i > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text('.', style: theme.textTheme.titleMedium),
                  ),
                Expanded(
                  child: Focus(
                    onKeyEvent: (_, event) => _onKey(i, event),
                    child: TextField(
                      controller: _fields[i],
                      focusNode: _nodes[i],
                      enabled: !_checking,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(3),
                      ],
                      onChanged: (v) => _onChanged(i, v),
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (_checking) ...[
            const SizedBox(height: 20),
            const Center(child: CircularProgressIndicator()),
          ],
          if (_status.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              _status,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
      actions: _checking
          ? null
          : [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.commonCancel),
              ),
              FilledButton(
                onPressed: _confirm,
                child: Text(l10n.commonOk),
              ),
            ],
    );
  }
}
