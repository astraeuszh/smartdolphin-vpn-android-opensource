import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../domain/account_datetime.dart';
import '../domain/auth_controller.dart';
import 'trial_status_banner.dart';

/// Single top-of-app banner with priority: ban > pending > trial > rate-limit.
class AccountFloatingBanner extends ConsumerWidget {
  const AccountFloatingBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final session = auth.session;
    if (session == null) return const SizedBox.shrink();
    final l10n = context.l10n;
    final policy = session.trafficPolicy;

    if (auth.status == AuthStatus.banned) {
      return _MessageBanner(
        text: auth.message ?? l10n.authBannedBanner,
        color: Colors.red.shade700,
      );
    }
    if (auth.status == AuthStatus.pending) {
      return _MessageBanner(
        text: auth.message ?? l10n.authPendingBanner,
        color: Colors.orange.shade800,
      );
    }
    if (session.isTrial) {
      return TrialStatusBanner(expireAt: session.expireAt);
    }
    if (policy.isViolationSpeedLimit) {
      return _MessageBanner(
        text: policy.throttleMessage.isNotEmpty
            ? policy.throttleMessage
            : l10n.riskPenaltyActive,
        color: Colors.red.shade600,
      );
    }
    return const SizedBox.shrink();
  }
}

class _MessageBanner extends StatelessWidget {
  const _MessageBanner({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.94),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ),
      ),
    );
  }
}
