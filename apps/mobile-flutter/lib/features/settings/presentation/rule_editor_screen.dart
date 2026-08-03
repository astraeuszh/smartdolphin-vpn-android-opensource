import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/error/app_error_handler.dart';
import '../../../core/legal_urls.dart';
import '../../../features/session/domain/session_controller.dart';
import '../../../features/session/domain/session_status.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/sdrl/sdrl_compiler.dart';
import '../../../services/sdrl/sdrl_diagnostic.dart';
import '../../../services/sdrl/sdrl_rule_store.dart';
import '../../../services/sdrl/sdrl_validator.dart';
import '../domain/preferences_controller.dart';
import '../domain/rule_draft.dart';
import '../domain/settings_controller.dart';
import 'sdrl_editor_panel.dart';

class RuleEditorScreen extends ConsumerStatefulWidget {
  const RuleEditorScreen({super.key});

  @override
  ConsumerState<RuleEditorScreen> createState() => _RuleEditorScreenState();
}

class _RuleEditorScreenState extends ConsumerState<RuleEditorScreen>
    with SafeScreenState {
  late CodeController _controller;
  final FocusNode _focusNode = FocusNode();
  Timer? _draftTimer;
  Timer? _validateTimer;
  bool _initialized = false;
  bool _saving = false;
  List<SdrlDiagnostic>? _compileErrors;
  List<SdrlDiagnostic> _liveErrors = const [];
  bool _validating = false;

  @override
  void initState() {
    super.initState();
    _controller = SdrlEditorPanel.createController('');
    _validateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(_runLiveValidation());
    });
  }

  String get _docUrl {
    final tag = ref.read(preferencesControllerProvider).localeCode;
    return LegalUrls.sdrlTutorialFor(tag);
  }

  String _fileTitle() {
    final draft = ref.read(ruleDraftProvider);
    final dbName =
        ref.read(settingsControllerProvider).routing.ruleDb.savedRuleName;
    final base = draft.savedFileName.isNotEmpty
        ? draft.savedFileName
        : (dbName.isNotEmpty ? dbName : SdrlRuleStore.tempName());
    final sanitized = SdrlRuleStore.sanitizeFileName(base);
    return '$sanitized${SdrlRuleStore.sdrlExt}';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final draft = ref.read(ruleDraftProvider);
    final initial = draft.text.isNotEmpty
        ? draft.text
        : ref.read(settingsControllerProvider).routing.ruleDb.customRules;
    _controller.text = initial;
    ref.read(ruleDraftProvider.notifier).updateText(initial);
    unawaited(_runLiveValidation(force: true));
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    _validateTimer?.cancel();
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  String get _text => _controller.text;

  Future<void> _runLiveValidation({bool force = false}) async {
    if (!screenAlive || _saving) return;
    if (_validating) return;
    _validating = true;
    try {
      final result = await SdrlValidator.validate(_text, force: force);
      if (!screenAlive) return;
      final next = result.errors;
      if (next.length != _liveErrors.length ||
          !_diagnosticsEqual(next, _liveErrors)) {
        safeSetState(() => _liveErrors = next);
      }
    } finally {
      _validating = false;
    }
  }

  bool _diagnosticsEqual(List<SdrlDiagnostic> a, List<SdrlDiagnostic> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].displayLine != b[i].displayLine) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    const bg = SdrlEditorPanel.bg;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (!await _confirmDiscardIfDirty()) return;
        if (mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 0.5,
          titleSpacing: 8,
          title: Text(
            _fileTitle(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          actions: [
            if (_saving)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(48, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: _save,
                  child: Text(
                    l10n.settingsRuleEditorSave,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
          ],
        ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_liveErrors.isNotEmpty)
                  Material(
                    color: const Color(0xFFFFEBEE),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: Text(
                        _liveErrors.map((e) => e.displayLine).join(' · '),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFC62828),
                          fontSize: 11,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: SdrlEditorPanel(
                    controller: _controller,
                    focusNode: _focusNode,
                    onChanged: _onTextChanged,
                  ),
                ),
              ],
            ),
            if (_saving)
              _CompilingOverlay(message: l10n.settingsRuleEditorCompiling),
            if (_compileErrors != null)
              _CompileErrorOverlay(
                errors: _compileErrors!,
                docUrl: _docUrl,
                onDismiss: () => safeSetState(() => _compileErrors = null),
                title: l10n.settingsRuleEditorErrorTitle,
                closeLabel: l10n.settingsRuleEditorErrorClose,
                docLabel: l10n.settingsRuleEditorSdrlHintLink,
              ),
          ],
        ),
      ),
    );
  }

  void _onTextChanged(String value) {
    if (value.length > SdrlEditorPanel.maxChars) {
      final trimmed = value.substring(0, SdrlEditorPanel.maxChars);
      _controller.text = trimmed;
      _controller.selection = TextSelection.collapsed(offset: trimmed.length);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.settingsRuleEditorInputLimit)),
        );
      }
      return;
    }
    SdrlEditorPanel.syncLanguage(_controller);
    if (_compileErrors != null) {
      safeSetState(() => _compileErrors = null);
    }
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 400), () {
      if (!screenAlive) return;
      ref.read(ruleDraftProvider.notifier).updateText(_controller.text);
    });
  }

  Future<void> _save() async {
    final text = _text;
    if (text.trim().isEmpty) {
      try {
        await ref.read(settingsControllerProvider.notifier).setCustomRules('');
        ref.read(ruleDraftProvider.notifier).markSaved(text: '', fileName: '');
      } catch (e, st) {
        debugPrint('[RuleEditor] clear save failed: $e\n$st');
      }
      if (mounted) Navigator.of(context).pop();
      return;
    }

    final defaultName = ref.read(ruleDraftProvider).savedFileName.isNotEmpty
        ? ref.read(ruleDraftProvider).savedFileName
        : SdrlRuleStore.tempName();
    final name = await _promptRuleName(defaultName);
    if (name == null || !mounted) return;

    safeSetState(() {
      _saving = true;
      _compileErrors = null;
    });

    try {
      final compiled = await SdrlCompiler.compile(text);
      if (!screenAlive) return;
      if (!compiled.ok) {
        safeSetState(() {
          _saving = false;
          _compileErrors = compiled.errors.isNotEmpty
              ? compiled.errors
              : [
                  SdrlDiagnostic(
                    severity: 'error',
                    code: 'E000',
                    message: compiled.firstErrorMessage,
                  ),
                ];
        });
        return;
      }

      await SdrlRuleStore.saveNamedRule(
        displayName: name,
        source: text,
        binary: compiled.binary,
        sourceHash: compiled.sourceHash,
      );
      await SdrlCompiler.persistResult(compiled, text);

      final connected =
          ref.read(sessionControllerProvider).status == SessionStatus.connected;

      await ref
          .read(settingsControllerProvider.notifier)
          .saveCompiledCustomRules(
            text: text,
            sourceHash: compiled.sourceHash,
            savedRuleName: SdrlRuleStore.sanitizeFileName(name),
            pendingReconnect: connected,
          );

      ref.read(ruleDraftProvider.notifier).markSaved(
            text: text,
            fileName: SdrlRuleStore.sanitizeFileName(name),
          );
      if (!mounted) return;
      safeSetState(() => _saving = false);
      Navigator.of(context).pop();
    } catch (e, st) {
      debugPrint('[RuleEditor] save failed: $e\n$st');
      if (!screenAlive) return;
      safeSetState(() {
        _saving = false;
        _compileErrors = [
          SdrlDiagnostic(
              severity: 'error', code: 'E000', message: e.toString()),
        ];
      });
    }
  }

  Future<String?> _promptRuleName(String initial) async {
    final l10n = context.l10n;
    final nameController = TextEditingController(text: initial);
    try {
      return await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.settingsRuleEditorSaveAsTitle),
          content: TextField(
            controller: nameController,
            autofocus: true,
            enableSuggestions: true,
            autocorrect: false,
            keyboardType: TextInputType.text,
            decoration: InputDecoration(
              labelText: l10n.settingsRuleEditorSaveAsLabel,
              hintText: l10n.settingsRuleEditorSaveAsHint,
              suffixText: SdrlRuleStore.sdrlExt,
            ),
            onSubmitted: (_) =>
                Navigator.of(ctx).pop(nameController.text.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l10n.settingsRuleEditorErrorClose),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(nameController.text.trim()),
              child: Text(l10n.settingsRuleEditorSave),
            ),
          ],
        ),
      );
    } finally {
      nameController.dispose();
    }
  }

  Future<bool> _confirmDiscardIfDirty() async {
    if (!ref.read(ruleDraftProvider).isDirty) return true;
    final l10n = context.l10n;
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.settingsRuleEditorUnsavedTitle),
        content: Text(l10n.settingsRuleEditorUnsavedBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.settingsRuleEditorUnsavedStay),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.settingsRuleEditorUnsavedDiscard),
          ),
        ],
      ),
    );
    if (discard == true) {
      try {
        await ref
            .read(settingsControllerProvider.notifier)
            .discardUnsavedRules();
      } catch (e, st) {
        debugPrint('[RuleEditor] discard failed: $e\n$st');
      }
    }
    return discard ?? false;
  }
}

class _CompilingOverlay extends StatelessWidget {
  const _CompilingOverlay({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black26,
      child: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              boxShadow: const [
                BoxShadow(color: Colors.black12, blurRadius: 8),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Text(message, style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CompileErrorOverlay extends StatelessWidget {
  const _CompileErrorOverlay({
    required this.errors,
    required this.docUrl,
    required this.onDismiss,
    required this.title,
    required this.closeLabel,
    required this.docLabel,
  });

  final List<SdrlDiagnostic> errors;
  final String docUrl;
  final VoidCallback onDismiss;
  final String title;
  final String closeLabel;
  final String docLabel;

  @override
  Widget build(BuildContext context) {
    final body = errors.map((e) => e.displayLine).join('\n\n');
    final height = MediaQuery.sizeOf(context).height;

    return Material(
      color: Colors.black38,
      child: SafeArea(
        child: Center(
          child: Container(
            margin: const EdgeInsets.all(12),
            height: height * 0.88,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE57373)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline,
                          color: Color(0xFFC62828), size: 20),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: onDismiss,
                        icon: const Icon(Icons.close, size: 20),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: SelectableText(
                      body,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        height: 1.45,
                        color: Color(0xFFB71C1C),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: () => launchUrl(
                          Uri.parse(docUrl),
                          mode: LaunchMode.externalApplication,
                        ),
                        child: Text(docLabel,
                            style: const TextStyle(fontSize: 12)),
                      ),
                      const Spacer(),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(64, 32),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        onPressed: onDismiss,
                        child: Text(closeLabel,
                            style: const TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
