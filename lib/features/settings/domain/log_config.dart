import 'package:equatable/equatable.dart';

/// Log configuration persisted and used by the app logger.
class LogConfig extends Equatable {
  const LogConfig({
    this.enabled = false,
    this.level = 'info',
    this.sizeLimitMb = 500,
    this.countLimit = 50,
  });

  final bool enabled;
  final String level; // debug, info, warn, error
  final int sizeLimitMb;
  final int countLimit;

  LogConfig copyWith({
    bool? enabled,
    String? level,
    int? sizeLimitMb,
    int? countLimit,
  }) =>
      LogConfig(
        enabled: enabled ?? this.enabled,
        level: level ?? this.level,
        sizeLimitMb: sizeLimitMb ?? this.sizeLimitMb,
        countLimit: countLimit ?? this.countLimit,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'level': level,
        'sizeLimitMb': sizeLimitMb,
        'countLimit': countLimit,
      };

  factory LogConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const LogConfig();
    return LogConfig(
      enabled: json['enabled'] as bool? ?? false,
      level: json['level'] as String? ?? 'info',
      sizeLimitMb: (json['sizeLimitMb'] as num?)?.toInt() ?? 500,
      countLimit: (json['countLimit'] as num?)?.toInt() ?? 50,
    );
  }

  bool get shouldLogDebug => enabled && (level == 'debug');
  bool get shouldLogInfo => enabled && ['debug', 'info'].contains(level);
  bool get shouldLogWarn => enabled && ['debug', 'info', 'warn'].contains(level);
  bool get shouldLogError => enabled;

  @override
  List<Object?> get props => [enabled, level, sizeLimitMb, countLimit];
}
