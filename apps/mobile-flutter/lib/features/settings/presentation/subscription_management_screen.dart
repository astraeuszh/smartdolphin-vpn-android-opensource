import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/top_snack.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/domain/account_datetime.dart';
import '../../auth/domain/auth_controller.dart';
import '../../settings/domain/preferences_controller.dart';

class SubscriptionManagementScreen extends ConsumerWidget {
  const SubscriptionManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final session = ref.watch(authControllerProvider).session;
    final localeTag =
        ref.watch(preferencesControllerProvider).localeCode ?? 'en';
    final theme = Theme.of(context);

    if (session == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.accountSubscriptionTitle)),
        body: Center(child: Text(l10n.accountLoginRequired)),
      );
    }

    final subscribedAt =
        session.subscribedAt > 0 ? session.subscribedAt : session.createdAt;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.accountSubscriptionTitle)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            l10n.accountSubscriptionIntro,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          _InfoTile(
            label: l10n.accountSubscriptionUid,
            value: session.publicUid.isEmpty
                ? '${session.uid}'
                : session.publicUid,
            onLongPress: () async {
              final uid = session.publicUid.isEmpty
                  ? '${session.uid}'
                  : session.publicUid;
              await Clipboard.setData(ClipboardData(text: uid));
              if (context.mounted) {
                showTopSnackBar(context, l10n.settingsLogPathCopied);
              }
            },
          ),
          _InfoTile(
            label: l10n.accountSubscriptionCreated,
            value: formatAccountDateTime(
              session.createdAt,
              localeTag: localeTag,
              l10n: l10n,
            ),
          ),
          _InfoTile(
            label: l10n.accountSubscriptionStarted,
            value: formatAccountDateTime(
              subscribedAt,
              localeTag: localeTag,
              l10n: l10n,
            ),
          ),
          _InfoTile(
            label: l10n.accountSubscriptionExpires,
            value: formatAccountDateTime(
              session.expireAt,
              localeTag: localeTag,
              l10n: l10n,
            ),
          ),
          if (session.isTrial) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Text(
                l10n.authTrialAccountHint(
                  formatTrialRemaining(session.expireAt, l10n),
                ),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.orange.shade900,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.label, required this.value, this.onLongPress});

  final String label;
  final String value;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          GestureDetector(
            onLongPress: onLongPress,
            behavior: HitTestBehavior.opaque,
            child: SelectableText(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
