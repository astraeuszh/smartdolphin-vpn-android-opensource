import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/legal_urls.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/storage/prefs.dart';
import '../../../services/remote/console_feedback.dart';
import '../domain/account_datetime.dart';
import '../domain/account_session.dart';
import '../domain/auth_controller.dart';

enum _Severity { green, yellow, orange, red }

class _AccountNotice {
  const _AccountNotice({
    required this.id,
    required this.signature,
    required this.text,
    required this.severity,
    this.dismissible = true,
    this.requireTypedConfirmation = false,
  });

  final String id;
  final String signature;
  final String text;
  final _Severity severity;
  final bool dismissible;
  final bool requireTypedConfirmation;
}

/// One compact status center. Independent restrictions remain visible together
/// instead of being hidden behind a single priority branch.
class AccountFloatingBanner extends ConsumerStatefulWidget {
  const AccountFloatingBanner({super.key});

  @override
  ConsumerState<AccountFloatingBanner> createState() =>
      _AccountFloatingBannerState();
}

class _AccountFloatingBannerState extends ConsumerState<AccountFloatingBanner>
    with WidgetsBindingObserver {
  Timer? _timer;
  Set<String> _dismissed = const {};
  String _loadedUser = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    // Status text is minute-granular; rebuilding every second needlessly keeps
    // the UI thread awake for the lifetime of every signed-in session.
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startTimer();
      if (mounted) setState(() {});
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _loadDismissed(String userKey) async {
    final prefs = await PrefsStore.create();
    final raw = prefs.getString('account_status.dismissed.$userKey') ?? '';
    if (!mounted || _loadedUser != userKey) return;
    setState(() => _dismissed =
        raw.split('|').where((item) => item.trim().isNotEmpty).toSet());
  }

  Future<void> _dismiss(String userKey, _AccountNotice notice) async {
    if (!notice.dismissible) return;
    final confirmed = await _confirmDismiss(notice);
    if (!confirmed || !mounted) return;
    final next = {..._dismissed, notice.signature};
    setState(() => _dismissed = next);
    final prefs = await PrefsStore.create();
    await prefs.setString('account_status.dismissed.$userKey', next.join('|'));
  }

  Future<bool> _confirmDismiss(_AccountNotice notice) async {
    if (notice.severity == _Severity.green) return true;
    final copy = _copy(context);
    final controller = TextEditingController();
    var accepted = false;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(copy.acknowledgeTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(copy.acknowledgeBody),
              const SizedBox(height: 12),
              _RestrictionLegalLinks(copy: copy),
              if (notice.requireTypedConfirmation) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: copy.typePrompt,
                    hintText: copy.typePhrase,
                  ),
                  onChanged: (_) => setDialogState(() {}),
                ),
              ] else ...[
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: accepted,
                  onChanged: (value) =>
                      setDialogState(() => accepted = value ?? false),
                  title: Text(copy.promise),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(copy.cancel),
            ),
            FilledButton(
              onPressed: (notice.requireTypedConfirmation
                      ? controller.text.trim() == copy.typePhrase
                      : accepted)
                  ? () => Navigator.pop(dialogContext, true)
                  : null,
              child: Text(copy.confirm),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    return result == true;
  }

  Future<void> _requestReview(
      AccountSession session, _AccountNotice notice) async {
    final copy = _copy(context);
    final controller = TextEditingController();
    var accepted = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(copy.reviewTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(copy.reviewBody),
              const SizedBox(height: 12),
              _RestrictionLegalLinks(copy: copy),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: accepted,
                onChanged: (value) =>
                    setDialogState(() => accepted = value ?? false),
                title: Text(copy.promise),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              TextField(
                controller: controller,
                decoration: InputDecoration(
                  labelText: copy.typePrompt,
                  hintText: copy.reviewPhrase,
                ),
                onChanged: (_) => setDialogState(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(copy.cancel),
            ),
            FilledButton(
              onPressed: accepted && controller.text.trim() == copy.reviewPhrase
                  ? () => Navigator.pop(dialogContext, true)
                  : null,
              child: Text(copy.submitReview),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (confirmed != true || !mounted) return;
    try {
      await ConsoleFeedback().submit(
        session: session,
        errorCode: 'ACCOUNT_RESTRICTION_REVIEW',
        message: '${notice.id}: ${notice.text}',
        logSnapshot: '',
        kind: 'unblock_request',
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(copy.reviewSent)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(copy.reviewFailed)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final session = auth.session;
    if (session == null) return const SizedBox.shrink();
    final userKey = session.publicUid.isNotEmpty
        ? session.publicUid
        : session.uid.toString();
    if (_loadedUser != userKey) {
      _loadedUser = userKey;
      _dismissed = const {};
      unawaited(_loadDismissed(userKey));
    }
    final visible = _notices(context, auth, session)
        .where((notice) => !_dismissed.contains(notice.signature))
        .toList();
    if (visible.isEmpty) return const SizedBox.shrink();

    return SafeArea(
      bottom: false,
      child: Material(
        color: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 280),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final notice in visible)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _NoticeBar(
                      notice: notice,
                      onTap: notice.severity == _Severity.red
                          ? () => unawaited(_requestReview(session, notice))
                          : null,
                      onClose: notice.dismissible
                          ? () => unawaited(_dismiss(userKey, notice))
                          : null,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

List<_AccountNotice> _notices(
    BuildContext context, AuthState auth, AccountSession session) {
  final copy = _copy(context);
  final policy = session.trafficPolicy;
  final notices = <_AccountNotice>[];
  if (session.isTrial) {
    notices.add(_AccountNotice(
      id: 'trial',
      signature: 'trial:${session.expireAt}',
      text: copy.trial(formatTrialRemaining(session.expireAt, context.l10n)),
      severity: _Severity.yellow,
      dismissible: false,
    ));
  } else if (session.expiresWithinOneDay) {
    notices.add(_AccountNotice(
      id: 'expiring',
      signature: 'expiring:${session.expireAt}',
      text: copy.expiring,
      severity: _Severity.yellow,
      dismissible: false,
    ));
  }
  if (auth.status == AuthStatus.expired || session.isExpired) {
    notices.add(_AccountNotice(
      id: 'expired',
      signature: 'expired:${session.expireAt}',
      text: copy.expired,
      severity: _Severity.red,
      dismissible: false,
    ));
  }
  if (policy.hasQuotaLimit) {
    notices.add(_AccountNotice(
      id: 'quota',
      signature:
          'quota:${policy.monthlyUsedGb}:${policy.monthlyQuotaGb}:${policy.overQuota}',
      text: copy.quota(policy.monthlyUsedGb, policy.monthlyQuotaGb,
          policy.quotaUtilization * 100),
      severity: _Severity.green,
    ));
  }
  if (policy.isViolationSpeedLimit) {
    notices.add(_AccountNotice(
      id: 'speed',
      signature: 'speed:${policy.speedLimitMbps}',
      text: copy.speed(policy.speedLimitMbps),
      severity: _Severity.orange,
    ));
  }
  if (policy.risk.lightCount > 0) {
    notices.add(_AccountNotice(
      id: 'light-violation',
      signature: 'light:${policy.risk.lightCount}',
      text: copy.lightViolation(policy.risk.lightCount),
      severity: _Severity.green,
    ));
  }
  if (policy.risk.mediumCount > 0) {
    notices.add(_AccountNotice(
      id: 'medium-violation',
      signature: 'medium:${policy.risk.mediumCount}',
      text: copy.mediumViolation(policy.risk.mediumCount),
      severity: _Severity.orange,
    ));
  }
  if (policy.risk.severeCount > 0 &&
      !session.locked &&
      !policy.isAccountLocked) {
    notices.add(_AccountNotice(
      id: 'severe-violation',
      signature: 'severe:${policy.risk.severeCount}',
      text: copy.severeViolation(policy.risk.severeCount),
      severity: _Severity.red,
      dismissible: false,
    ));
  }
  if (session.isMuted) {
    notices.add(_AccountNotice(
      id: 'muted',
      signature: 'muted:${session.mutedUntil}',
      text: copy.muted(session.mutedUntil),
      severity: _Severity.orange,
    ));
  }
  if (session.locked || policy.isAccountLocked) {
    notices.add(_AccountNotice(
      id: 'locked',
      signature: 'locked:${policy.risk.violationCount}',
      text: copy.locked(policy.risk.violationCount),
      severity: _Severity.red,
      dismissible: false,
      requireTypedConfirmation: true,
    ));
  }
  if (session.banned) {
    notices.add(_AccountNotice(
      id: 'banned',
      signature: 'banned:${session.banReason}',
      text: copy.banned(session.banReason),
      severity: _Severity.red,
      dismissible: false,
      requireTypedConfirmation: true,
    ));
  }
  return notices;
}

class _NoticeBar extends StatelessWidget {
  const _NoticeBar({required this.notice, this.onClose, this.onTap});
  final _AccountNotice notice;
  final VoidCallback? onClose;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = switch (notice.severity) {
      _Severity.green => (const Color(0xffe9f8ef), const Color(0xff197344)),
      _Severity.yellow => (const Color(0xfffff7d6), const Color(0xff8a6500)),
      _Severity.orange => (const Color(0xfffff0dc), const Color(0xffa54b00)),
      _Severity.red => (const Color(0xffffe7e7), const Color(0xffb42318)),
    };
    final bar = Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.$1.withValues(alpha: 0.97),
        border: Border.all(color: colors.$2.withValues(alpha: 0.34)),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
              color: Color(0x16000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: colors.$2),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              notice.text,
              style: TextStyle(
                color: colors.$2,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
          if (onClose != null)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              onPressed: onClose,
              icon: Icon(Icons.close_rounded, size: 19, color: colors.$2),
            ),
        ],
      ),
    );
    if (onTap == null) return bar;
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: bar,
      ),
    );
  }
}

class _RestrictionLegalLinks extends StatelessWidget {
  const _RestrictionLegalLinks({required this.copy});

  final _StatusCopy copy;

  @override
  Widget build(BuildContext context) {
    final localeTag = Localizations.localeOf(context).toLanguageTag();
    final style = Theme.of(context).textTheme.bodySmall;
    final linkStyle = style?.copyWith(
      color: Theme.of(context).colorScheme.primary,
      fontWeight: FontWeight.w700,
    );
    Future<void> open(String url) async {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }

    Widget link(String label, String url) => TextButton(
          onPressed: () => open(url),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(label, style: linkStyle),
        );

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 2,
      runSpacing: 2,
      children: [
        Text(copy.legalDocumentsPrefix, style: style),
        link(copy.bookTitle(copy.serviceTerms),
            LegalUrls.serviceTermsFor(localeTag)),
        link(copy.bookTitle(copy.communityRules),
            LegalUrls.communityRulesFor(localeTag)),
        link(copy.bookTitle(copy.violationPolicy),
            LegalUrls.violationPolicyFor(localeTag)),
      ],
    );
  }
}

class _StatusCopy {
  const _StatusCopy(this.language);
  final String language;

  bool get _zh => language == 'zh';
  bool get _hant => language == 'zh_Hant';
  bool get _ja => language == 'ja';
  bool get _es => language == 'es';

  String trial(String remaining) => _zh
      ? '当前为 1 天体验期，剩余 $remaining。'
      : _hant
          ? '目前為 1 天體驗期，剩餘 $remaining。'
          : _ja
              ? '1日間の体験期間です。残り $remaining。'
              : _es
                  ? 'Periodo de prueba de 1 día. Quedan $remaining.'
                  : 'You are on a 1-day trial. Remaining: $remaining.';
  String get expiring => _zh
      ? '订阅将在 24 小时内到期，请及时联系管理员续权。'
      : _hant
          ? '訂閱將在 24 小時內到期，請及時聯絡管理員續權。'
          : _ja
              ? 'サブスクリプションは24時間以内に期限切れになります。'
              : _es
                  ? 'La suscripción caduca en menos de 24 horas.'
                  : 'Your subscription expires within 24 hours.';
  String get expired => _zh
      ? '当前权限已到期。登录状态会保留，但 VPN 不可连接，请联系管理员续权。'
      : _hant
          ? '目前權限已到期。登入狀態會保留，但 VPN 無法連線，請聯絡管理員續權。'
          : _ja
              ? '権限の有効期限が切れました。ログイン状態は保持されますが、VPNには接続できません。'
              : _es
                  ? 'El acceso ha caducado. La sesión permanece iniciada, pero la VPN no puede conectarse.'
                  : 'Access has expired. You remain signed in, but VPN connection is disabled.';
  String quota(double used, double limit, double percent) => _zh || _hant
      ? '流量：已使用 ${used.toStringAsFixed(2)} GB / ${limit.toStringAsFixed(2)} GB（${percent.toStringAsFixed(1)}%）。'
      : 'Traffic: ${used.toStringAsFixed(2)} GB / ${limit.toStringAsFixed(2)} GB (${percent.toStringAsFixed(1)}%).';
  String speed(double value) => _zh || _hant
      ? '当前已被限速，最高速率 ${value.toStringAsFixed(value % 1 == 0 ? 0 : 1)} Mbps。'
      : 'Speed is restricted to ${value.toStringAsFixed(value % 1 == 0 ? 0 : 1)} Mbps.';
  String muted(int until) {
    final end = DateTime.fromMillisecondsSinceEpoch(until * 1000)
        .toLocal()
        .toString()
        .split('.')
        .first;
    return _zh
        ? '当前已被禁言，解除时间：$end。'
        : _hant
            ? '目前已被禁言，解除時間：$end。'
            : 'Messaging is restricted until $end.';
  }

  String locked(int count) => _zh || _hant
      ? '违规次数 ${count.clamp(0, 30)} / 30，账户已锁定，VPN 不可连接。'
      : 'Violation count ${count.clamp(0, 30)} / 30. The account is locked.';
  String banned(String reason) => _zh || _hant
      ? '账户已被封禁${reason.trim().isEmpty ? '。' : '：$reason'}'
      : 'The account is banned${reason.trim().isEmpty ? '.' : ': $reason'}';
  String lightViolation(int count) => _zh || _hant
      ? '检测到 $count 次轻度违规，请注意后续使用行为。'
      : '$count minor rule violation(s) detected. Please review your usage.';
  String mediumViolation(int count) => _zh || _hant
      ? '检测到 $count 次中度违规。关闭前需确认已阅读社区规则。'
      : '$count medium rule violation(s) detected. Review the community rules before dismissing.';
  String severeViolation(int count) => _zh || _hant
      ? '检测到 $count 次严重违规。点此向管理员申请复核。'
      : '$count severe rule violation(s) detected. Tap to request administrator review.';
  String get acknowledgeTitle => _zh
      ? '确认已知晓'
      : _hant
          ? '確認已知悉'
          : 'Acknowledge restriction';
  String get acknowledgeBody => _zh
      ? '关闭提示仅代表您已阅读并知晓当前限制，不会解除服务器端处罚。'
      : 'Closing this notice only confirms that you have read it. The server restriction remains active.';
  String get legalDocumentsPrefix => _zh
      ? '请阅读：'
      : _hant
          ? '請閱讀：'
          : _ja
              ? '次の文書を確認してください：'
              : _es
                  ? 'Lee los siguientes documentos: '
                  : 'Read the following documents: ';
  String get serviceTerms => _zh
      ? '服务条款'
      : _hant
          ? '服務條款'
          : _ja
              ? '利用規約'
              : _es
                  ? 'Términos del servicio'
                  : 'Terms of Service';
  String get communityRules => _zh
      ? '社区规则'
      : _hant
          ? '社群規則'
          : _ja
              ? 'コミュニティ規則'
              : _es
                  ? 'Reglas de la comunidad'
                  : 'Community Rules';
  String get violationPolicy => _zh
      ? '违规处理政策'
      : _hant
          ? '違規處理政策'
          : _ja
              ? '違反対応ポリシー'
              : _es
                  ? 'Política de infracciones'
                  : 'Violation Handling Policy';
  String bookTitle(String value) => _zh || _hant ? '《$value》' : value;
  String get promise =>
      _zh ? '我已阅读并会遵守相关规则。' : 'I have read and will follow these rules.';
  String get typePrompt => _zh ? '请输入确认文字' : 'Enter confirmation text';
  String get typePhrase => _zh
      ? '我已知晓'
      : _hant
          ? '我已知悉'
          : 'I UNDERSTAND';
  String get cancel => _zh ? '取消' : 'Cancel';
  String get confirm => _zh ? '确认' : 'Confirm';
  String get reviewTitle => _zh ? '申请解除限制' : 'Request restriction review';
  String get reviewBody => _zh
      ? '提交后管理员会复核当前限制。申请不会自动解除处罚，也不会重复加速处理。'
      : 'An administrator will review the restriction. Submission does not remove it automatically.';
  String get reviewPhrase =>
      _zh ? '我已知晓并承诺不再违规' : 'I UNDERSTAND AND WILL FOLLOW THE RULES';
  String get submitReview => _zh ? '提交申请' : 'Submit request';
  String get reviewSent =>
      _zh ? '申请已提交，请等待管理员复核。' : 'Review request submitted.';
  String get reviewFailed =>
      _zh ? '申请提交失败，请稍后重试。' : 'Request failed. Please retry.';
}

_StatusCopy _copy(BuildContext context) {
  final locale = Localizations.localeOf(context);
  final language = locale.languageCode == 'zh'
      ? (locale.scriptCode == 'Hant' || locale.countryCode == 'TW'
          ? 'zh_Hant'
          : 'zh')
      : locale.languageCode == 'ja'
          ? 'ja'
          : locale.languageCode == 'es'
              ? 'es'
              : 'en';
  return _StatusCopy(language);
}
