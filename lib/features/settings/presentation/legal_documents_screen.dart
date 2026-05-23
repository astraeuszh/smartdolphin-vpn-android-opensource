import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/legal_urls.dart';
import '../../../l10n/app_localizations.dart';

List<(String, String)> _legalDocs(BuildContext context) {
  final l10n = context.l10n;
  return [
    (LegalUrls.userAgreement, l10n.legalUserAgreement),
    (LegalUrls.openSourceLicense, l10n.legalOpenSource),
    (LegalUrls.legalNotice, l10n.legalNotice),
    (LegalUrls.disclaimer, l10n.legalDisclaimer),
  ];
}

Future<void> _openLegalUrl(String url) async {
  final uri = Uri.parse(url);
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    throw Exception('Cannot open $url');
  }
}

/// Legal documents — opens the hosted pages on doc.smartdolphin.top
class LegalDocumentsScreen extends StatelessWidget {
  const LegalDocumentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final docs = _legalDocs(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.legalDocsTitle),
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
                    SnackBar(content: Text('${context.l10n.legalDocsTitle}: $e')),
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
