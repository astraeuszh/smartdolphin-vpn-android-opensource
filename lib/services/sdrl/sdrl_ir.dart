import 'sdrl_diagnostic.dart';

class SdrlIrDocument {
  const SdrlIrDocument({
    required this.defaultAction,
    required this.rules,
    required this.sourceHash,
    this.warnings = const [],
  });

  factory SdrlIrDocument.fromJson(Map<String, dynamic> json) {
    final settings = json['settings'] as Map<String, dynamic>? ?? const {};
    final rulesJson = json['rules'] as List<dynamic>? ?? const [];
    final warningsJson = json['warnings'] as List<dynamic>? ?? const [];
    return SdrlIrDocument(
      defaultAction: settings['default_action'] as String? ?? 'proxy',
      sourceHash: json['source_hash'] as String? ?? '',
      rules: rulesJson
          .whereType<Map<String, dynamic>>()
          .map(SdrlIrRule.fromJson)
          .toList(),
      warnings: warningsJson
          .whereType<Map<String, dynamic>>()
          .map(
            (w) => SdrlDiagnostic(
              severity: 'warning',
              code: w['code'] as String? ?? 'W030',
              message: w['message'] as String? ?? '',
            ),
          )
          .toList(),
    );
  }

  final String defaultAction;
  final String sourceHash;
  final List<SdrlIrRule> rules;
  final List<SdrlDiagnostic> warnings;
}

class SdrlIrRule {
  const SdrlIrRule({
    required this.id,
    required this.action,
    required this.matchers,
    this.priority = 0,
    this.sourceLine,
  });

  factory SdrlIrRule.fromJson(Map<String, dynamic> json) {
    final action = json['action'] as Map<String, dynamic>? ?? const {};
    final matchersJson = json['matchers'] as List<dynamic>? ?? const [];
    return SdrlIrRule(
      id: json['id'] as String? ?? '',
      priority: json['priority'] as int? ?? 0,
      sourceLine: json['source_line'] as int?,
      action: action['type'] as String? ?? 'proxy',
      matchers: matchersJson
          .whereType<Map<String, dynamic>>()
          .map(SdrlIrMatcher.fromJson)
          .toList(),
    );
  }

  final String id;
  final int priority;
  final int? sourceLine;
  final String action;
  final List<SdrlIrMatcher> matchers;
}

class SdrlIrMatcher {
  const SdrlIrMatcher({
    required this.type,
    required this.value,
    this.op,
  });

  factory SdrlIrMatcher.fromJson(Map<String, dynamic> json) {
    return SdrlIrMatcher(
      type: json['type'] as String? ?? '',
      value: json['value'],
      op: json['op'] as String?,
    );
  }

  final String type;
  final dynamic value;
  final String? op;
}
