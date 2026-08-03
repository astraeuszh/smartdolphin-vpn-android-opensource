import 'package:equatable/equatable.dart';

class DataUsageState extends Equatable {
  static const Object _sentinel = Object();

  const DataUsageState({
    required this.periodStart,
    this.usedBytes = 0,
    this.monthlyLimitBytes,
    this.lastUpdated,
    this.pendingTraffic90Dialog = false,
    this.traffic90Warned = false,
  });

  factory DataUsageState.initial() => DataUsageState(
        periodStart: DateTime.now().toUtc(),
        usedBytes: 0,
      );

  final DateTime periodStart;

  /// Cumulative VPN tunnel bytes (lifetime until reset).
  final int usedBytes;
  final int? monthlyLimitBytes;
  final DateTime? lastUpdated;

  /// UI should show 90% quota dialog once, then clear via [clearTraffic90Dialog].
  final bool pendingTraffic90Dialog;

  /// Suppress repeated 90% prompts until usage drops below 90% or manual reset.
  final bool traffic90Warned;

  bool get hasLimit => monthlyLimitBytes != null && monthlyLimitBytes! > 0;

  bool get limitExceeded => hasLimit && usedBytes >= (monthlyLimitBytes ?? 0);

  double get utilization {
    final limit = monthlyLimitBytes;
    if (limit == null || limit <= 0) {
      return 0;
    }
    return usedBytes / limit;
  }

  DataUsageState copyWith({
    DateTime? periodStart,
    int? usedBytes,
    Object? monthlyLimitBytes = _sentinel,
    DateTime? lastUpdated,
    bool? pendingTraffic90Dialog,
    bool? traffic90Warned,
  }) {
    return DataUsageState(
      periodStart: periodStart ?? this.periodStart,
      usedBytes: usedBytes ?? this.usedBytes,
      monthlyLimitBytes: identical(monthlyLimitBytes, _sentinel)
          ? this.monthlyLimitBytes
          : monthlyLimitBytes as int?,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      pendingTraffic90Dialog:
          pendingTraffic90Dialog ?? this.pendingTraffic90Dialog,
      traffic90Warned: traffic90Warned ?? this.traffic90Warned,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'periodStart': periodStart.toIso8601String(),
      'usedBytes': usedBytes,
      'monthlyLimitBytes': monthlyLimitBytes,
      'lastUpdated': lastUpdated?.toIso8601String(),
      'pendingTraffic90Dialog': pendingTraffic90Dialog,
      'traffic90Warned': traffic90Warned,
    };
  }

  factory DataUsageState.fromJson(Map<String, dynamic> json) {
    return DataUsageState(
      periodStart:
          DateTime.tryParse(json['periodStart'] as String? ?? '')?.toUtc() ??
              DateTime.now().toUtc(),
      usedBytes: json['usedBytes'] as int? ?? 0,
      monthlyLimitBytes: json['monthlyLimitBytes'] as int?,
      lastUpdated:
          DateTime.tryParse(json['lastUpdated'] as String? ?? '')?.toUtc(),
      pendingTraffic90Dialog: json['pendingTraffic90Dialog'] as bool? ?? false,
      traffic90Warned: json['traffic90Warned'] as bool? ?? false,
    );
  }

  @override
  List<Object?> get props => [
        periodStart,
        usedBytes,
        monthlyLimitBytes,
        lastUpdated,
        pendingTraffic90Dialog,
        traffic90Warned
      ];
}
