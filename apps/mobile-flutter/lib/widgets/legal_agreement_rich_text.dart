import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/legal_urls.dart';
import '../features/settings/domain/preferences_controller.dart';
import '../l10n/app_localizations.dart';

typedef _LegalDocName = String Function(AppLocalizations l10n);

/// Inline legal links used on login and settings screens.
class LegalAgreementRichText extends ConsumerWidget {
  const LegalAgreementRichText({
    super.key,
    required this.hintTemplate,
    this.textAlign = TextAlign.center,
    this.wrapInBookTitleMarks = false,
  });

  final String hintTemplate;
  final TextAlign textAlign;
  final bool wrapInBookTitleMarks;

  static const _docSlugs = <(String slug, _LegalDocName nameOf)>[
    ('user-agreement', _userAgreementName),
    ('service-terms', _serviceTermsName),
    ('privacy-policy', _privacyPolicyName),
    ('cookie-policy', _cookiePolicyName),
    ('community-rules', _communityRulesName),
    ('violation-policy', _violationPolicyName),
    ('open-source-license', _openSourceName),
    ('disclaimer', _disclaimerName),
  ];

  static String _userAgreementName(AppLocalizations l) => l.legalUserAgreement;
  static String _serviceTermsName(AppLocalizations l) => l.legalServiceTerms;
  static String _privacyPolicyName(AppLocalizations l) =>
      l.privacyPolicyDialogTitle;
  static String _cookiePolicyName(AppLocalizations l) => l.legalCookiePolicy;
  static String _communityRulesName(AppLocalizations l) =>
      l.legalCommunityRules;
  static String _violationPolicyName(AppLocalizations l) =>
      l.legalViolationPolicy;
  static String _openSourceName(AppLocalizations l) => l.legalOpenSource;
  static String _disclaimerName(AppLocalizations l) => l.legalDisclaimer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final localeTag = ref.watch(preferencesControllerProvider).localeCode;
    final docs = LegalUrls.docsFor(localeTag);
    final theme = Theme.of(context);
    final base = theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.62),
          height: 1.5,
        ) ??
        const TextStyle(fontSize: 12);
    final linkStyle = base.copyWith(
      color: theme.colorScheme.primary,
      decoration: TextDecoration.underline,
      decorationColor: theme.colorScheme.primary.withValues(alpha: 0.6),
    );

    final separator = l10n.authLegalAgreementSeparator;
    const placeholder = '{agreements}';
    final placeholderIndex = hintTemplate.indexOf(placeholder);

    final docSpans = <InlineSpan>[];
    for (var i = 0; i < docs.length; i++) {
      final (url, slug) = docs[i];
      final nameOf = _docSlugs.firstWhere((d) => d.$1 == slug).$2;
      var label = nameOf(l10n);
      if (l10n.locale.languageCode == 'zh') {
        label = '《$label》';
      }
      docSpans.add(
        TextSpan(
          text: label,
          style: linkStyle,
          recognizer: TapGestureRecognizer()..onTap = () => _open(context, url),
        ),
      );
      if (i < docs.length - 1) {
        docSpans.add(TextSpan(text: separator, style: base));
      }
    }

    final children = <InlineSpan>[];
    if (placeholderIndex < 0) {
      children.add(TextSpan(text: hintTemplate, style: base));
      children.add(const TextSpan(text: ' '));
      children.addAll(docSpans);
    } else {
      final prefix = hintTemplate.substring(0, placeholderIndex);
      final suffix =
          hintTemplate.substring(placeholderIndex + placeholder.length);
      if (prefix.isNotEmpty) children.add(TextSpan(text: prefix, style: base));
      children.addAll(docSpans);
      if (suffix.isNotEmpty) children.add(TextSpan(text: suffix, style: base));
    }

    return Text.rich(
      TextSpan(children: children),
      textAlign: textAlign,
    );
  }

  Future<void> _open(BuildContext context, String url) async {
    try {
      final uri = Uri.parse(url);
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${context.l10n.legalDocsTitle}: $url')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${context.l10n.legalDocsTitle}: $e')),
        );
      }
    }
  }
}
