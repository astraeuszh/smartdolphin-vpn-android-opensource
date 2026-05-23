import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../domain/settings_controller.dart';
import '../domain/traffic_mode.dart';

/// Clash-style rule editor. One rule per line: CIDR (1.0.1.0/24) or domain.
class RuleEditorScreen extends ConsumerStatefulWidget {
  const RuleEditorScreen({super.key});

  @override
  ConsumerState<RuleEditorScreen> createState() => _RuleEditorScreenState();
}

class _RuleEditorScreenState extends ConsumerState<RuleEditorScreen> {
  late TextEditingController _controller;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _controller.text =
          ref.read(settingsControllerProvider).routing.ruleDb.customRules;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settingsRuleEditor),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              l10n.settingsRuleEditorHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _controller,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: InputDecoration(
                  hintText: '1.0.1.0/24\nbaidu.com\nwww.taobao.com',
                  border: const OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFamily: 'monospace',
                  fontSize: 13,
                ),
                onChanged: (_) => _saveDebounced(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              onPressed: () {
                _saveDebounced();
                Navigator.of(context).pop();
              },
              child: Text(l10n.close),
            ),
          ),
        ],
      ),
    );
  }

  void _saveDebounced() {
    ref.read(settingsControllerProvider.notifier).setCustomRules(_controller.text);
  }
}
