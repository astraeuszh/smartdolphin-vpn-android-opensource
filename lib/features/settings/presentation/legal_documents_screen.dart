import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/legal_urls.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/preferences_controller.dart';

List<(String, String)> _legalDocs(AppLocalizations l10n, String? localeTag) {
  return LegalUrls.docsFor(localeTag)
      .map((d) => (
            d.$1,
            switch (d.$2) {
              'user-agreement' => l10n.legalUserAgreement,
              'open-source-license' => l10n.legalOpenSource,
              'legal-notice' => l10n.legalNotice,
              'disclaimer' => l10n.legalDisclaimer,
              _ => d.$2,
            },
          ))
      .toList();
}

Future<void> _openLegalUrl(String url) async {
  final uri = Uri.parse(url);
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    throw Exception('Cannot open $url');
  }
}

/// Legal documents — opens the hosted pages on doc.smartdolphin.top
class LegalDocumentsScreen extends ConsumerWidget {
  const LegalDocumentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final localeTag = ref.watch(preferencesControllerProvider).localeCode;
    final docs = _legalDocs(l10n, localeTag);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.legalDocsTitle),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: docs.length,
        itemBuilder: (context, index) {
          final (url, title) = docs[index];
          return ListTile(
            leading: Icon(Icons.open_in_browser, color: theme.colorScheme.primary),
            title: Text(title),
            subtitle: Text(url, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              try {
                await _openLegalUrl(url);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('${l10n.legalDocsTitle}: $e')),
                  );
                }
              }
            },
          );
        },
      ),
    );
  }
}
