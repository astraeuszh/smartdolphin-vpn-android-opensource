import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../services/haptics/haptics_service.dart';
import '../../domain/game_decel_tier.dart';
import '../../domain/game_decel_tier_controller.dart';

enum GameDecelTierSectionVariant {
  settings,
  drawer,
}

class GameDecelTierSection extends ConsumerWidget {
  const GameDecelTierSection({
    super.key,
    this.variant = GameDecelTierSectionVariant.settings,
    this.showSectionTitle = true,
  });

  final GameDecelTierSectionVariant variant;
  final bool showSectionTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final tier = ref.watch(gameDecelTierProvider);
    final isDrawer = variant == GameDecelTierSectionVariant.drawer;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showSectionTitle) ...[
          Text(
            l10n.gameDecelSectionTitle,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: isDrawer ? 12 : 16),
        ],
        ...GameDecelTier.values.map(
          (t) => RadioListTile<GameDecelTier>(
            value: t,
            groupValue: tier,
            dense: isDrawer,
            visualDensity:
                isDrawer ? VisualDensity.compact : VisualDensity.standard,
            contentPadding: EdgeInsets.zero,
            title: Row(
              children: [
                Expanded(child: Text(_decelTierTitle(t, l10n))),
                IconButton(
                  tooltip: l10n.gameDecelTooltipHelp,
                  icon: Icon(
                    Icons.info_outline,
                    size: isDrawer ? 20 : 22,
                    color: cs.primary,
                  ),
                  onPressed: () => showDecelTierInfoDialog(context, ref, t, l10n),
                ),
              ],
            ),
            onChanged: (v) async {
              if (v == null) return;
              await ref.read(hapticsServiceProvider).selection();
              await ref.read(gameDecelTierProvider.notifier).setTier(v);
            },
          ),
        ),
      ],
    );
  }
}

String _decelTierTitle(GameDecelTier t, AppLocalizations l10n) {
  switch (t) {
    case GameDecelTier.low:
      return l10n.gameDecelTierLow;
    case GameDecelTier.medium:
      return l10n.gameDecelTierMedium;
    case GameDecelTier.high:
      return l10n.gameDecelTierHigh;
    case GameDecelTier.ultra:
      return l10n.gameDecelTierUltra;
  }
}

void showDecelTierInfoDialog(
  BuildContext context,
  WidgetRef ref,
  GameDecelTier t,
  AppLocalizations l10n,
) {
  unawaited(ref.read(hapticsServiceProvider).selection());
  late String title;
  late String body;
  switch (t) {
    case GameDecelTier.low:
      title = l10n.gameDecelTierLow;
      body = l10n.gameDecelInfoLowBody;
      break;
    case GameDecelTier.medium:
      title = l10n.gameDecelTierMedium;
      body = l10n.gameDecelInfoMediumBody;
      break;
    case GameDecelTier.high:
      title = l10n.gameDecelTierHigh;
      body = l10n.gameDecelInfoHighBody;
      break;
    case GameDecelTier.ultra:
      title = l10n.gameDecelTierUltra;
      body = l10n.gameDecelInfoUltraBody;
      break;
  }
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('$title · ${l10n.gameDecelTooltipHelp}'),
      content: SingleChildScrollView(child: Text(body)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(l10n.gameDecelInfoOk),
        ),
      ],
    ),
  );
}
