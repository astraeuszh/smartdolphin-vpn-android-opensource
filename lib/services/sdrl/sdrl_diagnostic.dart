class SdrlDiagnostic {
  const SdrlDiagnostic({
    required this.severity,
    required this.code,
    required this.message,
    this.line,
    this.col,
    this.help,
  });

  factory SdrlDiagnostic.fromJson(Map<String, dynamic> json) {
    return SdrlDiagnostic(
      severity: json['severity'] as String? ?? 'error',
      code: json['code'] as String? ?? 'E000',
      message: json['message'] as String? ?? '',
      line: json['line'] as int?,
      col: json['col'] as int?,
      help: json['help'] as String?,
    );
  }

  final String severity;
  final String code;
  final String message;
  final int? line;
  final int? col;
  final String? help;

  bool get isError => severity == 'error';

  String get displayLine {
    final loc = (line != null && line! > 0)
        ? ' (line $line${col != null ? ', col $col' : ''})'
        : '';
    final helpText = help == null || help!.isEmpty ? '' : '\nhelp: $help';
    return '$severity[$code]: $message$loc$helpText';
  }
}
