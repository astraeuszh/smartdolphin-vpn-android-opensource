import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/ui/top_snack.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/logging/vpn_core_layout.dart';
import '../../../services/logging/vpn_logger.dart';
import '../../../services/remote/console_auth.dart';
import '../../../services/remote/console_feedback.dart';
import '../../auth/domain/account_datetime.dart';
import '../../auth/domain/auth_controller.dart';
import '../../auth/domain/traffic_policy.dart';
import '../../auth/presentation/auth_gate_screen.dart';
import 'account_risk_screen.dart';
import 'subscription_management_screen.dart';
import '../domain/preferences_controller.dart';
import 'feedback_ticket_screen.dart';

const _websiteUrl = 'https://smartdolphin.top';
// Password reset is handled on the website (no in-app email-code flow).
const _passwordResetUrl = 'https://smartdolphinvpn.com';

class AccountSettingsScreen extends ConsumerStatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  ConsumerState<AccountSettingsScreen> createState() =>
      _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends ConsumerState<AccountSettingsScreen> {
  bool _refreshing = false;
  bool _busy = false;
  Timer? _trialTimer;

  @override
  void initState() {
    super.initState();
    _trialTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final session = ref.read(authControllerProvider).session;
      if (session?.isTrial == true && mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _trialTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshPolicy() async {
    final session = ref.read(authControllerProvider).session;
    if (session == null) return;
    setState(() => _refreshing = true);
    try {
      await ref.read(authControllerProvider.notifier).refreshSession();
    } catch (_) {
      if (mounted) {
        showTopSnackBar(context, context.l10n.accountRefreshFailed, isError: true);
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _openWebsite() async {
    final uri = Uri.parse(_websiteUrl);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        showTopSnackBar(context, context.l10n.accountOpenWebsiteFailed, isError: true);
      }
    }
  }

  Future<void> _confirmLogout() async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.accountLogout),
        content: Text(l10n.accountLogoutConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.accountLogout),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await ref.read(authControllerProvider.notifier).logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const AuthGateScreen()),
      (_) => false,
    );
  }

  Future<void> _openChangePassword() async {
    final l10n = context.l10n;
    final session = ref.read(authControllerProvider).session;
    if (session == null) return;

    final oldCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(l10n.accountChangePassword),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: oldCtrl,
                      obscureText: true,
                      decoration: InputDecoration(labelText: l10n.accountOldPassword),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: newCtrl,
                      obscureText: true,
                      decoration: InputDecoration(labelText: l10n.accountNewPassword),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: confirmCtrl,
                      obscureText: true,
                      decoration: InputDecoration(labelText: l10n.accountConfirmPassword),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: _busy
                            ? null
                            : () {
                                Navigator.of(ctx).pop();
                                unawaited(_openPasswordResetWebsite());
                              },
                        child: Text(l10n.accountForgotPassword),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: _busy ? null : () => Navigator.of(ctx).pop(),
                  child: Text(l10n.cancel),
                ),
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          if (newCtrl.text.length < 6) {
                            _snack(l10n.accountPasswordTooShort, isError: true);
                            return;
                          }
                          if (newCtrl.text != confirmCtrl.text) {
                            _snack(l10n.accountPasswordMismatch, isError: true);
                            return;
                          }
                          setDialogState(() => _busy = true);
                          try {
                            await ref.read(authControllerProvider.notifier).changePassword(
                                  oldPassword: oldCtrl.text,
                                  newPassword: newCtrl.text,
                                );
                            if (ctx.mounted) Navigator.of(ctx).pop();
                            _snack(l10n.accountUpdateSuccess);
                          } on ConsoleAuthException catch (e) {
                            _snack(e.message, isError: true);
                          } catch (e) {
                            _snack('$e', isError: true);
                          } finally {
                            setDialogState(() => _busy = false);
                          }
                        },
                  child: Text(l10n.accountSave),
                ),
              ],
            );
          },
        );
      },
    );

    oldCtrl.dispose();
    newCtrl.dispose();
    confirmCtrl.dispose();
  }

  /// Forgot password is handled on the website now (no in-app email-code flow).
  Future<void> _openPasswordResetWebsite() async {
    final uri = Uri.parse(_passwordResetUrl);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        showTopSnackBar(context, context.l10n.accountOpenWebsiteFailed,
            isError: true);
      }
    }
  }

  Future<void> _openChangeName() async {
    final l10n = context.l10n;
    final session = ref.read(authControllerProvider).session;
    if (session == null) return;

    final newCtrl = TextEditingController();
    final passCtrl = TextEditingController();

    await _showPasswordVerifiedDialog(
      title: l10n.accountChangeName,
      fields: [
        TextField(
          controller: newCtrl,
          decoration: InputDecoration(labelText: l10n.accountNewName),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: passCtrl,
          obscureText: true,
          decoration: InputDecoration(labelText: l10n.accountVerifyPassword),
        ),
      ],
      onSave: () async {
        await ref.read(authControllerProvider.notifier).updateUsername(
              oldUsername: session.username,
              newUsername: newCtrl.text,
              password: passCtrl.text,
            );
      },
    );

    newCtrl.dispose();
    passCtrl.dispose();
  }

  Future<void> _showPasswordVerifiedDialog({
    required String title,
    required List<Widget> fields,
    required Future<void> Function() onSave,
  }) async {
    final l10n = context.l10n;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(title),
              content: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: fields),
              ),
              actions: [
                TextButton(
                  onPressed: _busy ? null : () => Navigator.of(ctx).pop(),
                  child: Text(l10n.cancel),
                ),
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          setDialogState(() => _busy = true);
                          try {
                            await onSave();
                            if (ctx.mounted) Navigator.of(ctx).pop();
                            _snack(l10n.accountUpdateSuccess);
                          } on ConsoleAuthException catch (e) {
                            _snack(e.message, isError: true);
                          } catch (e) {
                            _snack('$e', isError: true);
                          } finally {
                            setDialogState(() => _busy = false);
                          }
                        },
                  child: Text(l10n.accountSave),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _openAdminFeedback() async {
    final l10n = context.l10n;
    final session = ref.read(authControllerProvider).session;
    if (session == null) return;

    final bytes =
        await ref.read(vpnLoggerProvider).estimateFeedbackSnapshotBytes();
    final sizeLabel = _formatBytes(bytes);
    final trafficKb = (bytes / 1024).ceil().clamp(1, 9999);

    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.accountFeedbackAdmin),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.accountFeedbackAdminBody),
              const SizedBox(height: 16),
              Text(
                l10n.accountFeedbackLogSize(sizeLabel),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Text(l10n.accountFeedbackDataUsage(trafficKb)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.accountFeedbackDecline),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.accountFeedbackConfirm),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final logger = ref.read(vpnLoggerProvider);
      final snapshot = await logger.buildFeedbackSnapshot(
        window: VpnCoreLayout.manualFeedbackWindow,
      );
      await ConsoleFeedback().submit(
        session: session,
        errorCode: kFeedbackManualErrorCode,
        kind: 'admin_feedback',
        message: 'Manual feedback from Android account settings',
        logSnapshot: snapshot,
      );
      _snack(l10n.accountFeedbackSubmitted);
    } catch (e) {
      _snack('${l10n.accountFeedbackFailed}: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String message, {bool isError = false}) {
    if (!mounted) return;
    showTopSnackBar(context, message, isError: isError);
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }

  String _avatarLetter(String username) {
    final trimmed = username.trim();
    if (trimmed.isEmpty) return '?';
    return trimmed[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final auth = ref.watch(authControllerProvider);
    final session = auth.session;
    final theme = Theme.of(context);
    final policy = session?.trafficPolicy ?? const TrafficPolicy();
    final localeTag = ref.watch(preferencesControllerProvider).localeCode ?? 'en';

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settingsAccountManageTitle),
        actions: [
          IconButton(
            onPressed: _refreshing || session == null ? null : _refreshPolicy,
            icon: _refreshing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: session == null
          ? Center(child: Text(l10n.accountLoginRequired))
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Center(
                  child: CircleAvatar(
                    radius: 44,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Text(
                      _avatarLetter(session.username),
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    session.username,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (session.email.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Center(
                    child: Text(
                      session.email,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
                if (auth.status == AuthStatus.banned) ...[
                  const SizedBox(height: 16),
                  _warnCard(
                    theme,
                    auth.message ?? l10n.authBannedBanner,
                    color: Colors.red.shade700,
                  ),
                ],
                if (auth.status == AuthStatus.pending) ...[
                  const SizedBox(height: 16),
                  _warnCard(
                    theme,
                    auth.message ?? l10n.authPendingBanner,
                    color: Colors.orange.shade800,
                  ),
                ],
                if (session.isTrial) ...[
                  const SizedBox(height: 16),
                  _warnCard(
                    theme,
                    l10n.authTrialAccountHint(
                      formatTrialRemaining(session.expireAt, l10n),
                    ),
                    color: Colors.red.shade700,
                  ),
                ],
                if (policy.isViolationSpeedLimit) ...[
                  const SizedBox(height: 16),
                  _warnCard(
                    theme,
                    policy.throttleMessage.isNotEmpty
                        ? policy.throttleMessage
                        : '您因违反用户规则，暂时对您的账户进行限速处理，但连接仍可用，请遵循使用规范。',
                    color: Colors.red.shade600,
                  ),
                ],
                if (policy.isQuotaExceeded) ...[
                  const SizedBox(height: 16),
                  _warnCard(
                    theme,
                    '本月流量已用完（${policy.monthlyQuotaGb.toStringAsFixed(0)} GB 上限）',
                    color: Colors.red.shade700,
                  ),
                ],
                if (policy.hasQuotaLimit && !policy.isQuotaExceeded) ...[
                  const SizedBox(height: 24),
                  Text(
                    '流量套餐：${policy.monthlyQuotaGb.toStringAsFixed(0)} GB / 月',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: policy.quotaUtilization,
                      minHeight: 8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.accountQuotaSummary(
                      policy.monthlyQuotaGb,
                      policy.monthlyUsedGb,
                      policy.quotaUtilization * 100,
                    ),
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
                const SizedBox(height: 32),
                _menuTile(
                  icon: Icons.card_membership_outlined,
                  title: l10n.accountSubscriptionTitle,
                  subtitle: session.isTrial
                      ? l10n.authTrialRemainingShort(
                          formatTrialRemaining(session.expireAt, l10n),
                        )
                      : formatAccountDateTime(
                          session.expireAt,
                          localeTag: localeTag,
                          l10n: l10n,
                        ),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const SubscriptionManagementScreen(),
                      ),
                    );
                  },
                ),
                _menuTile(
                  icon: Icons.shield_outlined,
                  title: l10n.riskTitle,
                  subtitle: l10n.riskMenuSummary(
                    policy.risk.violationCount,
                    policy.risk.trafficLimitCount,
                  ),
                  onTap: _busy
                      ? null
                      : () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => AccountRiskScreen(
                                risk: policy.risk,
                                policy: policy,
                              ),
                            ),
                          );
                        },
                ),
                _menuTile(
                  icon: Icons.lock_outline,
                  title: l10n.accountChangePassword,
                  onTap: _busy ? null : _openChangePassword,
                ),
                _menuTile(
                  icon: Icons.badge_outlined,
                  title: l10n.accountChangeName,
                  onTap: _busy ? null : _openChangeName,
                ),
                const Divider(height: 32),
                _menuTile(
                  icon: Icons.support_agent_outlined,
                  title: l10n.accountFeedbackAdmin,
                  onTap: _busy ? null : _openAdminFeedback,
                ),
                _menuTile(
                  icon: Icons.assignment_outlined,
                  title: l10n.accountFeedbackTicket,
                  onTap: _busy
                      ? null
                      : () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const FeedbackTicketScreen(),
                            ),
                          );
                        },
                ),
                _menuTile(
                  icon: Icons.language_outlined,
                  title: l10n.accountContactUs,
                  onTap: _openWebsite,
                ),
                _menuTile(
                  icon: Icons.info_outline,
                  title: l10n.accountAboutUs,
                  onTap: _openWebsite,
                ),
                const Divider(height: 32),
                _menuTile(
                  icon: Icons.logout,
                  title: l10n.accountLogout,
                  titleColor: Colors.redAccent,
                  onTap: _busy ? null : _confirmLogout,
                ),
              ],
            ),
    );
  }

  Widget _menuTile({
    required IconData icon,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
    Color? titleColor,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(title, style: titleColor != null ? TextStyle(color: titleColor) : null),
      subtitle: subtitle == null ? null : Text(subtitle),
      isThreeLine: subtitle != null,
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }

  Widget _warnCard(ThemeData theme, String message, {Color? color}) {
    final base = color ?? theme.colorScheme.error;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: base.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: base.withValues(alpha: 0.55),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: base),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(color: base),
            ),
          ),
        ],
      ),
    );
  }
}
