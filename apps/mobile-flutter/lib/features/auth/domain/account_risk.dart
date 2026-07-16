class AccountRisk {
  const AccountRisk({
    this.violationCount = 0,
    this.trafficLimitCount = 0,
    this.penaltyUntil = 0,
    this.lightCount = 0,
    this.mediumCount = 0,
    this.severeCount = 0,
  });

  final int violationCount;
  final int trafficLimitCount;
  final int penaltyUntil;
  final int lightCount;
  final int mediumCount;
  final int severeCount;

  /// Retained for callers that render the legacy field name. Traffic quotas
  /// are intentionally excluded: only conduct violations lock the account.
  int get totalStrikes => violationCount;

  /// A server-side policy can permanently lock an account at 30 violations.
  /// Keep the client-side gate as a fast fail-safe while the API remains the
  /// authority for enforcement.
  bool get locked => violationCount >= 30;

  bool get underPenalty {
    if (penaltyUntil <= 0) return false;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return now < penaltyUntil;
  }

  static AccountRisk fromJson(Map<String, dynamic> data) {
    return AccountRisk(
      violationCount: _asInt(data['violation_count']),
      trafficLimitCount: _asInt(data['traffic_limit_count']),
      penaltyUntil: _asInt(data['risk_penalty_until']),
      lightCount: _asInt(data['light_violation_count']),
      mediumCount: _asInt(data['medium_violation_count']),
      severeCount: _asInt(data['severe_violation_count']),
    );
  }

  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }
}
