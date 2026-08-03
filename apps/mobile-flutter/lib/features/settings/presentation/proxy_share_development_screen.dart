import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

class ProxyShareDevelopmentScreen extends StatefulWidget {
  const ProxyShareDevelopmentScreen({super.key});

  @override
  State<ProxyShareDevelopmentScreen> createState() =>
      _ProxyShareDevelopmentScreenState();
}

class _ProxyShareDevelopmentScreenState
    extends State<ProxyShareDevelopmentScreen> {
  int _mode = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsProxyShare)),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
        child: Column(
          children: [
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(
                    value: 0,
                    label: Text('内网传输'),
                    icon: Icon(Icons.lan_outlined)),
                ButtonSegment(
                    value: 1,
                    label: Text('公网传输'),
                    icon: Icon(Icons.public_rounded)),
              ],
              selected: {_mode},
              showSelectedIcon: false,
              onSelectionChanged: (value) =>
                  setState(() => _mode = value.first),
            ),
            const Spacer(),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    shape: BoxShape.circle,
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: Icon(
                    Icons.fence_rounded,
                    size: 40,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  l10n.settingsFeatureInDevelopment,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}
