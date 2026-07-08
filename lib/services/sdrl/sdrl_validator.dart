import 'sdrl_diagnostic.dart';

/// Validates SDRL rule source — lightweight live checks; full compile only on save.
class SdrlValidator {
  SdrlValidator._();

  static const liveValidateMaxChars = 32768;

  static Future<SdrlValidationResult> validate(
    String source, {
    bool force = false,
  }) async {
    final trimmed = source.trim();
    if (trimmed.isEmpty) {
      return SdrlValidationResult.ok(ruleCount: 0);
    }

    if (!force && trimmed.length > liveValidateMaxChars) {
      return SdrlValidationResult.deferred();
    }

    final errors = <SdrlDiagnostic>[];

    final versionErr = _checkVersionLine(trimmed);
    if (versionErr != null) errors.add(versionErr);

    if (!trimmed.contains('version') && versionErr == null) {
      errors.add(const SdrlDiagnostic(
        severity: 'error',
        code: 'E001',
        message: '缺少 version 声明（例如 version 1.0;）',
      ));
    }

    final braceErr = _checkBraces(trimmed);
    if (braceErr != null) errors.add(braceErr);

    errors.addAll(_checkLineIssues(trimmed));

    if (errors.isNotEmpty) {
      return SdrlValidationResult.error(diagnostics: errors);
    }

    if (!trimmed.contains('profile') && !trimmed.contains('rule')) {
      return SdrlValidationResult.error(
        diagnostics: [
          const SdrlDiagnostic(
            severity: 'error',
            code: 'E002',
            message: '缺少 profile 或 rule 声明。',
          ),
        ],
      );
    }

    return SdrlValidationResult.ok(ruleCount: 0);
  }

  static SdrlDiagnostic? _checkVersionLine(String text) {
    final lines = text.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty || line.startsWith('//')) continue;
      if (!RegExp(r'^v', caseSensitive: false).hasMatch(line) &&
          !line.toLowerCase().contains('version')) {
        continue;
      }
      if (RegExp(r'^v\s*version\b', caseSensitive: false).hasMatch(line) ||
          RegExp(r'^vv\s*ersion\b', caseSensitive: false).hasMatch(line)) {
        return SdrlDiagnostic(
          severity: 'error',
          code: 'E010',
          message: 'version 拼写或格式可能有误，应为 version 1.0;',
          line: i + 1,
        );
      }
      if (RegExp(r'^version\b', caseSensitive: false).hasMatch(line) &&
          !line.contains(';')) {
        return SdrlDiagnostic(
          severity: 'error',
          code: 'E011',
          message: 'version 行末尾缺少分号 ;',
          line: i + 1,
        );
      }
      break;
    }
    return null;
  }

  static List<SdrlDiagnostic> _checkLineIssues(String text) {
    final out = <SdrlDiagnostic>[];
    final lines = text.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final raw = lines[i];
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('//')) continue;
      if (line.contains('rule') &&
          line.contains('{') &&
          !line.contains('}') &&
          !line.endsWith(';') &&
          !line.endsWith('{')) {
        out.add(SdrlDiagnostic(
          severity: 'warning',
          code: 'W001',
          message: 'rule 行可能缺少分号或左大括号',
          line: i + 1,
        ));
      }
    }
    return out;
  }

  static SdrlDiagnostic? _checkBraces(String text) {
    var depth = 0;
    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      if (c == '{') depth++;
      if (c == '}') {
        depth--;
        if (depth < 0) {
          return SdrlDiagnostic(
            severity: 'error',
            code: 'E003',
            message: '大括号不匹配（多余的 }）',
            line: _lineOf(text, i),
          );
        }
      }
    }
    if (depth != 0) {
      return const SdrlDiagnostic(
        severity: 'error',
        code: 'E003',
        message: '大括号不匹配（缺少 }）',
      );
    }
    return null;
  }

  static int _lineOf(String text, int index) {
    var line = 1;
    for (var i = 0; i < index && i < text.length; i++) {
      if (text.codeUnitAt(i) == 10) line++;
    }
    return line;
  }
}

class SdrlValidationResult {
  const SdrlValidationResult._({
    required this.valid,
    this.diagnostics = const [],
    this.ruleCount = 0,
    this.warnings = const [],
    this.deferred = false,
  });

  factory SdrlValidationResult.ok({
    required int ruleCount,
    List<SdrlDiagnostic> warnings = const [],
  }) =>
      SdrlValidationResult._(
        valid: true,
        ruleCount: ruleCount,
        warnings: warnings,
      );

  factory SdrlValidationResult.error({
    List<SdrlDiagnostic> diagnostics = const [],
  }) =>
      SdrlValidationResult._(
        valid: false,
        diagnostics: diagnostics,
      );

  factory SdrlValidationResult.deferred() => const SdrlValidationResult._(
        valid: true,
        deferred: true,
      );

  final bool valid;
  final List<SdrlDiagnostic> diagnostics;
  final int ruleCount;
  final List<SdrlDiagnostic> warnings;
  final bool deferred;

  List<SdrlDiagnostic> get errors =>
      diagnostics.where((d) => d.isError).toList();

  String? get message =>
      errors.isNotEmpty ? errors.first.displayLine : null;
}
