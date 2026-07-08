import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/top_snack.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/logging/vpn_core_layout.dart';
import '../../../services/logging/vpn_logger.dart';
import '../../../services/remote/console_feedback.dart';
import '../../auth/domain/account_risk.dart';
import '../../auth/domain/auth_controller.dart';
import '../../auth/domain/traffic_policy.dart';

class AccountRiskScreen extends ConsumerStatefulWidget {
  const AccountRiskScreen({
    super.key,
    required this.risk,
    required this.policy,
  });

  final AccountRisk risk;
  final TrafficPolicy policy;

  @override
  ConsumerState<AccountRiskScreen> createState() => _AccountRiskScreenState();
}

class _AccountRiskScreenState extends ConsumerState<AccountRiskScreen> {
  bool _submitting = false;

  Future<void> _submitUnblockRequest() async {
    if (_submitting) return;
    final l10n = AppLocalizations.of(context);
    final session = ref.read(authControllerProvider).session;
    if (session == null) return;
    setState(() => _submitting = true);
    try {
      // 附带运行日志，方便管理员判断是否误限制（此前 unblock 请求不带任何日志）。
      final snapshot = await ref.read(vpnLoggerProvider).buildFeedbackSnapshot(
            window: VpnCoreLayout.manualFeedbackWindow,
          );
      await ConsoleFeedback().submit(
        session: session,
        errorCode: 'E0000',
        kind: 'unblock_request',
        message: l10n.riskUnblockMessage(
            widget.risk.violationCount, widget.risk.trafficLimitCount),
        logSnapshot: snapshot,
      );
      if (!mounted) return;
      showTopSnackBar(context, l10n.riskReported);
    } catch (e) {
      if (!mounted) return;
      showTopSnackBar(context, l10n.riskReportFailed('$e'), isError: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final risk = widget.risk;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.riskTitle)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            '${l10n.riskExplain}\n${l10n.riskExplainBan}\n${l10n.riskExplainLimit}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          _StatTile(
            label: l10n.riskBanCount,
            value: '${risk.violationCount}',
          ),
          _StatTile(
            label: l10n.riskLimitCount,
            value: '${risk.trafficLimitCount}',
          ),
          _StatTile(
            label: l10n.riskTotalCount,
            value: '${risk.totalStrikes} / 30',
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: _submitting ? null : _submitUnblockRequest,
              icon: _submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.support_agent_outlined),
              label: Text(_submitting ? l10n.riskReporting : l10n.riskReportButton),
            ),
          ),
          if (risk.underPenalty) ...[
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                l10n.riskPenaltyActive,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      trailing: Text(
        value,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}
