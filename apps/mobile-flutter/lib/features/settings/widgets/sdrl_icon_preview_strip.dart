import 'package:flutter/material.dart';

import '../../../core/ui/sdrl_icon.dart';
import '../../../l10n/app_localizations.dart';

/// Preview row for SDRL unified icons (.sdrl / .sdrb / sdrlc).
class SdrlIconPreviewStrip extends StatelessWidget {
  const SdrlIconPreviewStrip({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          _chip(context, label: '.sdrl', caption: context.l10n.sdrlIconSource),
          const SizedBox(width: 12),
          _chip(context, label: '.sdrb', caption: context.l10n.sdrlIconBinary),
          const SizedBox(width: 12),
          _chip(context,
              label: 'sdrlc', caption: context.l10n.sdrlIconCompiled),
        ],
      ),
    );
  }

  Widget _chip(
    BuildContext context, {
    required String label,
    required String caption,
  }) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          const SdrlIcon(size: 40),
          const SizedBox(height: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            caption,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }
}
