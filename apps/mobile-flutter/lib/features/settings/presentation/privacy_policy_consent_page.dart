import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/legal_urls.dart';
import '../../../l10n/app_localizations.dart';

class PrivacyPolicyConsentPage extends StatefulWidget {
  const PrivacyPolicyConsentPage({super.key});

  @override
  State<PrivacyPolicyConsentPage> createState() =>
      _PrivacyPolicyConsentPageState();
}

class _PrivacyPolicyConsentPageState extends State<PrivacyPolicyConsentPage> {
  bool _isChecked = false;
  String? _helperMessage;

  void _handleCheckboxChanged(bool? value) {
    setState(() {
      _isChecked = value ?? false;
      _helperMessage = null;
    });
  }

  void _handleContinue() {
    final l10n = context.l10n;
    if (!_isChecked) {
      setState(() {
        _helperMessage = l10n.privacyPolicyAgreementRequired;
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  Future<void> _openPrivacyPolicy() async {
    final uri = Uri.parse(LegalUrls.privacyPolicyFor(
      Localizations.localeOf(context).toLanguageTag(),
    ));
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      setState(() => _helperMessage = context.l10n.privacyPolicyOpenFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(l10n.privacyPolicyDialogTitle),
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: constraints.maxWidth > 720 ? 48 : 24,
                      vertical: 16,
                    ),
                    child: Column(
                      children: [
                        Expanded(
                          child: Center(
                            child: FilledButton.icon(
                              onPressed: _openPrivacyPolicy,
                              icon: const Icon(Icons.open_in_browser_outlined),
                              label: Text(l10n.privacyPolicyOpenDocs),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        CheckboxListTile(
                          value: _isChecked,
                          onChanged: _handleCheckboxChanged,
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                          title: Text(l10n.privacyPolicyCheckboxLabel),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            l10n.privacyPolicyAvailableInSettings,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color:
                                  theme.colorScheme.onSurface.withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                        if (_helperMessage != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.secondaryContainer
                                   .withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              _helperMessage!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSecondaryContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const SizedBox.shrink(),
                            FilledButton(
                              onPressed: _handleContinue,
                              child: Text(l10n.privacyPolicyAgreeButton),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
