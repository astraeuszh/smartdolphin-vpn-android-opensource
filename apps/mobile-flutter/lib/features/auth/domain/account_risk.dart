class AccountRisk {
  const AccountRisk({
    this.violationCount = 0,
    this.trafficLimitCount = 0,
    this.penaltyUntil = 0,
  });

  final int violationCount;
  final int trafficLimitCount;
  final int penaltyUntil;

  int get totalStrikes => violationCount + trafficLimitCount;

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
    );
  }

  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }
}
