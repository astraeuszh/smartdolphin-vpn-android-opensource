import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/legal_urls.dart';
import '../l10n/app_localizations.dart';

typedef _LegalDocName = String Function(AppLocalizations l10n);

/// Inline legal links used on login and settings screens.
class LegalAgreementRichText extends StatelessWidget {
  const LegalAgreementRichText({
    super.key,
    required this.hintTemplate,
    this.textAlign = TextAlign.center,
    this.wrapInBookTitleMarks = false,
  });

  final String hintTemplate;
  final TextAlign textAlign;
  final bool wrapInBookTitleMarks;

  static const _docs = <(String, _LegalDocName)>[
    (LegalUrls.userAgreement, _userAgreementName),
    (LegalUrls.openSourceLicense, _openSourceName),
    (LegalUrls.legalNotice, _legalNoticeName),
    (LegalUrls.disclaimer, _disclaimerName),
  ];

  static String _userAgreementName(AppLocalizations l) => l.legalUserAgreement;
  static String _openSourceName(AppLocalizations l) => l.legalOpenSource;
  static String _legalNoticeName(AppLocalizations l) => l.legalNotice;
  static String _disclaimerName(AppLocalizations l) => l.legalDisclaimer;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
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
    for (var i = 0; i < _docs.length; i++) {
      final (url, nameOf) = _docs[i];
      var label = nameOf(l10n);
      if (wrapInBookTitleMarks && l10n.locale.languageCode == 'zh') {
        label = '《$label》';
      }
      docSpans.add(
        TextSpan(
          text: label,
          style: linkStyle,
          recognizer: TapGestureRecognizer()
            ..onTap = () => _open(context, url),
        ),
      );
      if (i < _docs.length - 1) {
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
      final suffix = hintTemplate.substring(placeholderIndex + placeholder.length);
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
