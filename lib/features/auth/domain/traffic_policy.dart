class TrafficPolicy {
  const TrafficPolicy({
    this.hasPolicy = false,
    this.throttled = false,
    this.throttleMessage = '',
    this.monthlyQuotaGb = 0,
    this.monthlyUsedGb = 0,
    this.overQuota = false,
  });

  final bool hasPolicy;
  final bool throttled;
  final String throttleMessage;
  final double monthlyQuotaGb;
  final double monthlyUsedGb;
  final bool overQuota;

  bool get hasQuotaLimit => monthlyQuotaGb > 0;

  int? get serverMaxLimitBytes =>
      hasQuotaLimit ? (monthlyQuotaGb * 1024 * 1024 * 1024).round() : null;

  double get quotaUtilization =>
      hasQuotaLimit ? (monthlyUsedGb / monthlyQuotaGb).clamp(0, 1) : 0;

  static TrafficPolicy fromJson(Map<String, dynamic> data) {
    final quotaGb = _asDouble(data['monthly_quota_gb']);
    final usedGb = _asDouble(data['monthly_used_gb']);
    final throttled = data['throttle'] == true;
    final overQuota = data['over_quota'] == true;
    final hasPolicy = data['has_traffic_policy'] == true ||
        throttled ||
        overQuota ||
        quotaGb > 0 ||
        usedGb > 0;
    return TrafficPolicy(
      hasPolicy: hasPolicy,
      throttled: throttled,
      throttleMessage: (data['throttle_message'] as String?) ?? '',
      monthlyQuotaGb: quotaGb,
      monthlyUsedGb: usedGb,
      overQuota: overQuota,
    );
  }

  static double _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? 0;
  }
}
