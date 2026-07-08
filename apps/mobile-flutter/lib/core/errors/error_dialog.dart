import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'error_codes.dart';

/// Error dialog aligned with Windows ErrorModal. English, brief message + code.
class ErrorDialog extends StatelessWidget {
  const ErrorDialog({
    super.key,
    required this.message,
    required this.errorCode,
    this.title = 'Error',
    this.onClose,
  });

  final String message;
  final int errorCode;
  final String title;
  final VoidCallback? onClose;

  static String formatCode(int code) => formatErrorCode(code);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.error_outline, color: theme.colorScheme.error, size: 28),
          const SizedBox(width: 12),
          Text(title, style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.bold)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 12),
          Text(
            context.l10n.errorDialogCodeLabel(formatCode(errorCode)),
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              color: theme.colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop();
            onClose?.call();
          },
          child: Text(context.l10n.close),
        ),
      ],
    );
  }
}

/// Show error dialog. Returns when dialog is closed.
Future<void> showErrorDialog(
  BuildContext context, {
  required String message,
  required int errorCode,
  String title = 'Error',
  VoidCallback? onClose,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => ErrorDialog(
      message: message,
      errorCode: errorCode,
      title: title,
      onClose: onClose,
    ),
  );
}
