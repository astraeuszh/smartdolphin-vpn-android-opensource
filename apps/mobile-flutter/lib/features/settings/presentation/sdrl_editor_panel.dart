import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_highlight/themes/atom-one-light.dart';
import 'package:highlight/languages/rust.dart';

/// Compact white SDRL editor panel.
class SdrlEditorPanel extends StatelessWidget {
  const SdrlEditorPanel({
    super.key,
    required this.controller,
    required this.focusNode,
    this.onChanged,
  });

  final CodeController controller;
  final FocusNode focusNode;
  final ValueChanged<String>? onChanged;

  static const maxChars = 1048576;
  static const bg = Color(0xFFFAFAFA);
  static const textColor = Color(0xFF383A42);
  static const gutterColor = Color(0xFF9DA5B4);

  static CodeController createController(String text) {
    final c = CodeController(text: text, language: rust);
    c.autocompleter.setCustomWords(const [
      'version', 'settings', 'profile', 'rule', 'match',
      'domain.suffix', 'domain', 'ip.cidr', 'port',
      'direct', 'proxy', 'reject', 'block', 'default',
      'set', 'priority', 'and', 'in', 'import',
    ]);
    return c;
  }

  static void syncLanguage(CodeController controller) {
    controller.language =
        controller.text.length > 65536 ? null : rust;
  }

  static double gutterWidthFor(String text) {
    final lines = text.isEmpty ? 1 : '\n'.allMatches(text).length + 1;
    final digits = math.max(2, lines.toString().length);
    return 8.0 + digits * 9.0;
  }

  @override
  Widget build(BuildContext context) {
    syncLanguage(controller);
    final gutterW = gutterWidthFor(controller.text);

    return ColoredBox(
      color: bg,
      child: CodeTheme(
        data: CodeThemeData(styles: atomOneLightTheme),
        child: CodeField(
          controller: controller,
          focusNode: focusNode,
          expands: true,
          wrap: false,
          background: bg,
          onChanged: onChanged,
          smartDashesType: SmartDashesType.disabled,
          smartQuotesType: SmartQuotesType.disabled,
          gutterStyle: GutterStyle(
            showLineNumbers: controller.text.length <= 262144,
            width: gutterW,
            margin: 4,
            textAlign: TextAlign.right,
            textStyle: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 10,
              height: 1.35,
              color: gutterColor,
            ),
          ),
          textStyle: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            height: 1.35,
            color: textColor,
          ),
          decoration: const BoxDecoration(color: bg),
        ),
      ),
    );
  }
}
