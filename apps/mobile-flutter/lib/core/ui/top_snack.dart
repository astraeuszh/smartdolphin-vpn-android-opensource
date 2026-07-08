import 'package:flutter/material.dart';

/// Shows a floating snack bar near the top of the screen (errors, confirmations).
void showTopSnackBar(
  BuildContext context,
  String message, {
  bool isError = false,
  Duration duration = const Duration(seconds: 4),
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        message,
        style: TextStyle(
          color: isError
              ? Theme.of(context).colorScheme.onErrorContainer
              : Theme.of(context).colorScheme.onInverseSurface,
        ),
      ),
      duration: duration,
      behavior: SnackBarBehavior.floating,
      backgroundColor: isError
          ? Theme.of(context).colorScheme.errorContainer
          : Theme.of(context).colorScheme.inverseSurface,
      margin: EdgeInsets.only(
        left: 16,
        right: 16,
        top: MediaQuery.paddingOf(context).top + 8,
      ),
    ),
  );
}
