import 'account_risk.dart';

class TrafficPolicy {
  const TrafficPolicy({
    this.hasPolicy = false,
    this.throttled = false,
    this.throttleMessage = '',
    this.monthlyQuotaGb = 0,
    this.monthlyUsedGb = 0,
    this.overQuota = false,
    this.risk = const AccountRisk(),
  });

  final bool hasPolicy;
  final bool throttled;
  final String throttleMessage;
  final double monthlyQuotaGb;
  final double monthlyUsedGb;
  final bool overQuota;
  final AccountRisk risk;

  bool get hasQuotaLimit => monthlyQuotaGb > 0;

  /// Admin / violation speed limit — not the same as monthly quota exhaustion.
  bool get isViolationSpeedLimit => throttled && !overQuota;

  /// Monthly quota exhausted (usage cap, not a community-rule violation).
  bool get isQuotaExceeded => overQuota;

  int? get serverMaxLimitBytes =>
      hasQuotaLimit ? (monthlyQuotaGb * 1024 * 1024 * 1024).round() : null;

  double get quotaUtilization =>
      hasQuotaLimit ? (monthlyUsedGb / monthlyQuotaGb).clamp(0, 1) : 0;

  static TrafficPolicy fromJson(Map<String, dynamic> data) {
    final quotaGb = _asDouble(data['monthly_quota_gb']);
    final usedGb = _asDouble(data['monthly_used_gb']);
    final throttled = data['throttle'] == true;
    final overQuota = data['over_quota'] == true;
    // 仅在服务器明确标记 has_traffic_policy 为 true 时认为存在策略；
    // 这样后台清除限额（has_traffic_policy=false）能强制覆盖客户端缓存。
    final hasPolicy = data['has_traffic_policy'] == true || quotaGb > 0;
    return TrafficPolicy(
      hasPolicy: hasPolicy,
      throttled: throttled,
      throttleMessage: (data['throttle_message'] as String?) ?? '',
      monthlyQuotaGb: hasPolicy ? quotaGb : 0,
      monthlyUsedGb: usedGb,
      overQuota: overQuota,
      risk: AccountRisk.fromJson(data),
    );
  }

  /// Merge server fields into cached policy; omit keys preserve existing values.
  TrafficPolicy mergeFrom(Map<String, dynamic> data) {
    final parsed = TrafficPolicy.fromJson(data);
    final hasRisk = data.containsKey('violation_count') ||
        data.containsKey('traffic_limit_count') ||
        data.containsKey('risk_penalty_until');
    final hasTraffic = data.containsKey('throttle') ||
        data.containsKey('has_traffic_policy') ||
        data.containsKey('monthly_quota_gb') ||
        data.containsKey('over_quota');
    return TrafficPolicy(
      hasPolicy: hasTraffic ? parsed.hasPolicy : hasPolicy,
      throttled: hasTraffic ? parsed.throttled : throttled,
      throttleMessage: hasTraffic && parsed.throttleMessage.isNotEmpty
          ? parsed.throttleMessage
          : throttleMessage,
      monthlyQuotaGb: hasTraffic ? parsed.monthlyQuotaGb : monthlyQuotaGb,
      monthlyUsedGb: hasTraffic ? parsed.monthlyUsedGb : monthlyUsedGb,
      overQuota: hasTraffic ? parsed.overQuota : overQuota,
      risk: hasRisk ? parsed.risk : risk,
    );
  }

  static double _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? 0;
  }
}
