import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/top_snack.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/logging/vpn_core_layout.dart';
import '../../../services/logging/vpn_logger.dart';
import '../../../services/remote/console_feedback.dart';
import '../../auth/domain/account_risk.dart';
import '../../auth/domain/account_session.dart';
import '../../auth/domain/auth_controller.dart';
import '../../auth/domain/traffic_policy.dart';
import 'support_chat_screen.dart';

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

class _AccountRiskScreenState extends ConsumerState<AccountRiskScreen>
    with WidgetsBindingObserver {
  bool _submitting = false;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startClock();
  }

  void _startClock() {
    _clock?.cancel();
    // Restriction countdowns are displayed at minute precision.
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startClock();
      setState(() {});
    } else {
      _clock?.cancel();
      _clock = null;
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _submitUnblockRequest() async {
    if (_submitting) return;
    final l10n = AppLocalizations.of(context);
    final session = ref.read(authControllerProvider).session;
    if (session == null) return;
    setState(() => _submitting = true);
    try {
      final snapshot = await ref.read(vpnLoggerProvider).buildFeedbackSnapshot(
            window: VpnCoreLayout.manualFeedbackWindow,
          );
      await ConsoleFeedback().submit(
        session: session,
        errorCode: 'E0000',
        kind: 'unblock_request',
        message: l10n.riskUnblockMessage(
          widget.risk.violationCount,
          widget.risk.trafficLimitCount,
        ),
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
    final copy = _RiskCopy.of(context);
    final session = ref.watch(authControllerProvider).session;
    final policy = session?.trafficPolicy ?? widget.policy;
    final risk = session?.trafficPolicy.risk ?? widget.risk;
    final restrictions = _activeRestrictions(copy, session, policy, risk);

    return Scaffold(
      appBar: AppBar(title: Text(copy.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        children: [
          Text(
            copy.summary(risk.violationCount.clamp(0, 30)),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          _StatTile(
            label: copy.violationCount,
            value: '${risk.violationCount.clamp(0, 30)} / 30',
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) => Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [
                SizedBox(
                  width: constraints.maxWidth >= 420
                      ? (constraints.maxWidth - 10) / 2
                      : constraints.maxWidth,
                  child: FilledButton.tonalIcon(
                    onPressed: _submitting ? null : _submitUnblockRequest,
                    icon: _submitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.gavel_outlined),
                    label: Text(_submitting ? copy.submitting : copy.appeal),
                  ),
                ),
                SizedBox(
                  width: constraints.maxWidth >= 420
                      ? (constraints.maxWidth - 10) / 2
                      : constraints.maxWidth,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SupportChatScreen(),
                      ),
                    ),
                    icon: const Icon(Icons.support_agent_outlined),
                    label: Text(copy.contact),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(
                child: Text(
                  copy.activeRestrictions,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${restrictions.length}',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            copy.permanentHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          if (restrictions.isEmpty)
            _HealthyRow(text: copy.noRestrictions)
          else
            for (var i = 0; i < restrictions.length; i++) ...[
              _RestrictionRow(restriction: restrictions[i]),
              if (i != restrictions.length - 1) const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }
}

enum _RiskSeverity { green, orange, red }

class _Restriction {
  const _Restriction({
    required this.icon,
    required this.title,
    required this.detail,
    required this.severity,
  });

  final IconData icon;
  final String title;
  final String detail;
  final _RiskSeverity severity;
}

List<_Restriction> _activeRestrictions(
  _RiskCopy copy,
  AccountSession? session,
  TrafficPolicy policy,
  AccountRisk risk,
) {
  final items = <_Restriction>[];
  if (session != null && session.isExpired) {
    items.add(_Restriction(
      icon: Icons.event_busy_outlined,
      title: copy.expiredTitle,
      detail: copy.expiredDetail,
      severity: _RiskSeverity.red,
    ));
  }
  if (policy.isQuotaExceeded) {
    final percent = policy.monthlyQuotaGb <= 0
        ? 0.0
        : policy.monthlyUsedGb / policy.monthlyQuotaGb * 100;
    items.add(_Restriction(
      icon: Icons.data_usage_outlined,
      title: copy.quotaTitle,
      detail: copy.quotaDetail(
        policy.monthlyUsedGb,
        policy.monthlyQuotaGb,
        percent,
      ),
      severity: _RiskSeverity.green,
    ));
  }
  if (policy.isViolationSpeedLimit) {
    items.add(_Restriction(
      icon: Icons.speed_outlined,
      title: copy.speedTitle,
      detail: copy.speedDetail(policy.speedLimitMbps),
      severity: _RiskSeverity.orange,
    ));
  }
  if (session?.isMuted == true) {
    items.add(_Restriction(
      icon: Icons.mic_off_outlined,
      title: copy.mutedTitle,
      detail: copy.mutedDetail(session!.mutedUntil),
      severity: _RiskSeverity.orange,
    ));
  }
  if (session?.locked == true || policy.isAccountLocked) {
    items.add(_Restriction(
      icon: Icons.lock_outline_rounded,
      title: copy.lockedTitle,
      detail: copy.lockedDetail(risk.violationCount.clamp(0, 30)),
      severity: _RiskSeverity.red,
    ));
  }
  if (session?.banned == true) {
    items.add(_Restriction(
      icon: Icons.block_outlined,
      title: copy.bannedTitle,
      detail: copy.bannedDetail(session!.banReason),
      severity: _RiskSeverity.red,
    ));
  }
  return items;
}

class _RestrictionRow extends StatelessWidget {
  const _RestrictionRow({required this.restriction});

  final _Restriction restriction;

  @override
  Widget build(BuildContext context) {
    final colors = switch (restriction.severity) {
      _RiskSeverity.green => (const Color(0xffe9f8ef), const Color(0xff197344)),
      _RiskSeverity.orange => (
          const Color(0xfffff0dc),
          const Color(0xffa54b00)
        ),
      _RiskSeverity.red => (const Color(0xffffe7e7), const Color(0xffb42318)),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 11, 14, 11),
      decoration: BoxDecoration(
        color: colors.$1,
        border: Border(left: BorderSide(color: colors.$2, width: 3)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(restriction.icon, color: colors.$2, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  restriction.title,
                  style: TextStyle(
                    color: colors.$2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  restriction.detail,
                  style: TextStyle(color: colors.$2, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HealthyRow extends StatelessWidget {
  const _HealthyRow({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xffedf8f1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            const Icon(Icons.verified_outlined, color: Color(0xff197344)),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
          ],
        ),
      );
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => ListTile(
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

class _RiskCopy {
  const _RiskCopy(this.language);
  final String language;

  bool get _zh => language == 'zh';
  bool get _hant => language == 'zh_Hant';
  bool get _ja => language == 'ja';
  bool get _es => language == 'es';

  static _RiskCopy of(BuildContext context) {
    final locale = Localizations.localeOf(context);
    if (locale.languageCode == 'zh') {
      return _RiskCopy(locale.scriptCode == 'Hant' || locale.countryCode == 'TW'
          ? 'zh_Hant'
          : 'zh');
    }
    return _RiskCopy(
      locale.languageCode == 'ja'
          ? 'ja'
          : locale.languageCode == 'es'
              ? 'es'
              : 'en',
    );
  }

  String get title => _zh
      ? '账户违规'
      : _hant
          ? '帳戶違規'
          : _ja
              ? 'アカウント制限'
              : _es
                  ? 'Restricciones de la cuenta'
                  : 'Account restrictions';
  String summary(int count) => _zh
      ? '当前违规次数：$count / 30。达到 30 次后，VPN 将保持锁定，直到账户通过管理员复核。'
      : _hant
          ? '目前違規次數：$count / 30。達到 30 次後，VPN 將保持鎖定，直到帳戶通過管理員覆核。'
          : _ja
              ? '現在の違反回数：$count / 30。30 回に達すると、管理者の確認が完了するまで VPN はロックされます。'
              : _es
                  ? 'Infracciones actuales: $count / 30. Al llegar a 30, la VPN quedará bloqueada hasta la revisión del administrador.'
                  : 'Current violations: $count / 30. At 30, VPN access remains locked until an administrator reviews the account.';
  String get violationCount => _zh
      ? '违规次数'
      : _hant
          ? '違規次數'
          : _ja
              ? '違反回数'
              : _es
                  ? 'Infracciones'
                  : 'Violation count';
  String get appeal => _zh
      ? '请求复核'
      : _hant
          ? '請求覆核'
          : _ja
              ? '審査を申請'
              : _es
                  ? 'Solicitar revisión'
                  : 'Request review';
  String get submitting => _zh
      ? '正在提交'
      : _hant
          ? '正在提交'
          : _ja
              ? '送信中'
              : _es
                  ? 'Enviando'
                  : 'Submitting';
  String get contact => _zh
      ? '联系客服'
      : _hant
          ? '聯絡客服'
          : _ja
              ? 'サポートに連絡'
              : _es
                  ? 'Contactar soporte'
                  : 'Contact support';
  String get activeRestrictions => _zh
      ? '当前限制'
      : _hant
          ? '目前限制'
          : _ja
              ? '現在の制限'
              : _es
                  ? 'Restricciones activas'
                  : 'Active restrictions';
  String get permanentHint => _zh
      ? '此处始终展示服务器记录的有效限制，关闭顶部提示不会删除这些记录。'
      : _hant
          ? '此處始終顯示伺服器記錄的有效限制，關閉頂部提示不會刪除這些記錄。'
          : _ja
              ? 'サーバーに記録された有効な制限を常に表示します。上部の通知を閉じても削除されません。'
              : _es
                  ? 'Aquí siempre se muestran las restricciones activas del servidor. Cerrar un aviso superior no las elimina.'
                  : 'Active server restrictions always appear here. Dismissing a top notice does not remove them.';
  String get noRestrictions => _zh
      ? '当前没有有效限制。'
      : _hant
          ? '目前沒有有效限制。'
          : _ja
              ? '現在、有効な制限はありません。'
              : _es
                  ? 'No hay restricciones activas.'
                  : 'There are no active restrictions.';

  String get expiredTitle => _zh
      ? '订阅已到期'
      : _hant
          ? '訂閱已到期'
          : _ja
              ? 'サブスクリプション期限切れ'
              : _es
                  ? 'Suscripción caducada'
                  : 'Subscription expired';
  String get expiredDetail => _zh
      ? '登录状态会保留，但续权前无法连接 VPN。'
      : _hant
          ? '登入狀態會保留，但續權前無法連線 VPN。'
          : _ja
              ? 'ログイン状態は維持されますが、更新するまで VPN には接続できません。'
              : _es
                  ? 'La sesión seguirá iniciada, pero la VPN no podrá conectarse hasta la renovación.'
                  : 'You remain signed in, but VPN access is disabled until renewal.';
  String get quotaTitle => _zh
      ? '流量额度已用尽'
      : _hant
          ? '流量額度已用盡'
          : _ja
              ? '通信量上限超過'
              : _es
                  ? 'Cuota de tráfico agotada'
                  : 'Traffic quota exceeded';
  String quotaDetail(double used, double limit, double percent) => _zh || _hant
      ? '已使用 ${used.toStringAsFixed(2)} GB / ${limit.toStringAsFixed(2)} GB（${percent.toStringAsFixed(1)}%）'
      : _ja
          ? '${used.toStringAsFixed(2)} GB / ${limit.toStringAsFixed(2)} GB 使用済み（${percent.toStringAsFixed(1)}%）'
          : _es
              ? '${used.toStringAsFixed(2)} GB de ${limit.toStringAsFixed(2)} GB usados (${percent.toStringAsFixed(1)} %)'
              : '${used.toStringAsFixed(2)} GB / ${limit.toStringAsFixed(2)} GB used (${percent.toStringAsFixed(1)}%)';
  String get speedTitle => _zh
      ? '连接已限速'
      : _hant
          ? '連線已限速'
          : _ja
              ? '速度制限中'
              : _es
                  ? 'Velocidad limitada'
                  : 'Speed restricted';
  String speedDetail(double speed) => _zh || _hant
      ? '当前最高速率为 ${_number(speed)} Mbps。'
      : _ja
          ? '現在の最高速度は ${_number(speed)} Mbps です。'
          : _es
              ? 'La velocidad máxima actual es de ${_number(speed)} Mbps.'
              : 'Current maximum speed is ${_number(speed)} Mbps.';
  String get mutedTitle => _zh
      ? '消息功能已禁用'
      : _hant
          ? '訊息功能已停用'
          : _ja
              ? 'メッセージ送信制限'
              : _es
                  ? 'Mensajería restringida'
                  : 'Messaging restricted';
  String mutedDetail(int until) {
    final end = DateTime.fromMillisecondsSinceEpoch(until * 1000).toLocal();
    final remaining = Duration(
        seconds: (until - DateTime.now().millisecondsSinceEpoch ~/ 1000)
            .clamp(0, 1 << 31));
    final time =
        '${end.year.toString().padLeft(4, '0')}-${end.month.toString().padLeft(2, '0')}-${end.day.toString().padLeft(2, '0')} ${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}:${end.second.toString().padLeft(2, '0')}';
    final left = _duration(remaining);
    return _zh
        ? '解除时间：$time（剩余 $left）'
        : _hant
            ? '解除時間：$time（剩餘 $left）'
            : _ja
                ? '解除時刻：$time（残り $left）'
                : _es
                    ? 'Finaliza: $time (quedan $left)'
                    : 'Ends: $time ($left remaining)';
  }

  String get lockedTitle => _zh
      ? '账户已锁定'
      : _hant
          ? '帳戶已鎖定'
          : _ja
              ? 'アカウントロック'
              : _es
                  ? 'Cuenta bloqueada'
                  : 'Account locked';
  String lockedDetail(int count) => _zh
      ? '违规次数 $count / 30，管理员复核前无法连接 VPN。'
      : _hant
          ? '違規次數 $count / 30，管理員覆核前無法連線 VPN。'
          : _ja
              ? '違反回数 $count / 30。管理者の確認まで VPN に接続できません。'
              : _es
                  ? '$count / 30 infracciones. La VPN queda desactivada hasta la revisión.'
                  : '$count / 30 violations. VPN remains disabled pending review.';
  String get bannedTitle => _zh
      ? '账户已封禁'
      : _hant
          ? '帳戶已封禁'
          : _ja
              ? 'アカウント停止'
              : _es
                  ? 'Cuenta suspendida'
                  : 'Account banned';
  String bannedDetail(String reason) {
    final clean = reason.trim();
    if (clean.isEmpty) {
      return _zh
          ? '该账户已被管理员封禁。'
          : _hant
              ? '該帳戶已被管理員封禁。'
              : _ja
                  ? 'このアカウントは管理者により停止されています。'
                  : _es
                      ? 'La cuenta ha sido suspendida por un administrador.'
                      : 'The account has been banned by an administrator.';
    }
    return _zh
        ? '原因：$clean'
        : _hant
            ? '原因：$clean'
            : _ja
                ? '理由：$clean'
                : _es
                    ? 'Motivo: $clean'
                    : 'Reason: $clean';
  }

  String _number(double value) => value.toStringAsFixed(value % 1 == 0 ? 0 : 1);
  String _duration(Duration value) {
    final days = value.inDays;
    final hours = value.inHours.remainder(24);
    final minutes = value.inMinutes.remainder(60);
    final seconds = value.inSeconds.remainder(60);
    if (_zh || _hant) {
      return days > 0
          ? '$days 天 $hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}'
          : '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return days > 0
        ? '${days}d $hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}'
        : '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
