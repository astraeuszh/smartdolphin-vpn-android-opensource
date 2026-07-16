import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/legal_urls.dart';
import '../../../l10n/app_localizations.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final uri = Uri.parse(LegalUrls.privacyPolicyFor(
      Localizations.localeOf(context).toLanguageTag(),
    ));
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.privacyPolicyDialogTitle),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: FilledButton.icon(
            onPressed: () =>
                launchUrl(uri, mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.open_in_browser_outlined),
            label: Text(l10n.privacyPolicyOpenDocs),
          ),
        ),
      ),
    );
  }
}
