import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'sdrl_diagnostic.dart';
import 'sdrl_ir.dart';
import 'sdrl_rule_store.dart';

/// Compiles SDRL source via native sdrl-core (libsdrl_ffi.so) or sdrlc CLI.
class SdrlCompiler {
  SdrlCompiler._();

  static DynamicLibrary? _lib;
  static int Function(Pointer<Utf8>, Pointer<Pointer<Utf8>>)? _compileJsonFn;
  static void Function(Pointer<Utf8>)? _freeFn;

  static const irFileName = SdrlRuleStore.irFileName;
  static const binFileName =
      '${SdrlRuleStore.activeBase}${SdrlRuleStore.sdrbExt}';
  static const sourceFileName =
      '${SdrlRuleStore.activeBase}${SdrlRuleStore.sdrlExt}';

  static Future<SdrlCompileResult> compile(String source) async {
    final trimmed = source.trim();
    if (trimmed.isEmpty) {
      return SdrlCompileResult.ok(
        ir: null,
        binary: Uint8List(0),
        sourceHash: '',
        diagnostics: const [],
        ruleCount: 0,
      );
    }

    final native = _compileNative(trimmed);
    if (native != null) return native;

    if (!kIsWeb &&
        (Platform.isLinux || Platform.isMacOS || Platform.isWindows)) {
      final cli = await _compileViaCli(trimmed);
      if (cli != null) return cli;
    }

    return SdrlCompileResult.failure(
      diagnostics: [
        const SdrlDiagnostic(
          severity: 'error',
          code: 'E000',
          message:
              'SDRL compiler is unavailable. Update the app or contact support (missing libsdrl_ffi.so).',
        ),
      ],
    );
  }

  static Future<SdrlCompileResult> compileAndPersist(String source) async {
    final result = await compile(source);
    if (!result.ok) return result;
    await persistResult(result, source);
    return result;
  }

  static Future<void> persistResult(
      SdrlCompileResult result, String source) async {
    final dir = await _sdrlDir();
    await dir.create(recursive: true);
    await File('${dir.path}/$sourceFileName').writeAsString(source);
    if (result.ir != null) {
      await File('${dir.path}/$irFileName').writeAsString(
        jsonEncode({
          'sdrl_ir': 1,
          'source_hash': result.sourceHash,
          'settings': {'default_action': result.ir!.defaultAction},
          'rules': result.ir!.rules
              .map(
                (r) => {
                  'id': r.id,
                  'priority': r.priority,
                  'source_line': r.sourceLine,
                  'matchers': r.matchers
                      .map(
                          (m) => {'type': m.type, 'value': m.value, 'op': m.op})
                      .toList(),
                  'action': {'type': r.action},
                },
              )
              .toList(),
          'warnings': result.warnings
              .map((w) => {'code': w.code, 'message': w.message})
              .toList(),
        }),
      );
    } else {
      final irFile = File('${dir.path}/$irFileName');
      if (await irFile.exists()) await irFile.delete();
    }
    if (result.binary.isNotEmpty) {
      await File('${dir.path}/$binFileName').writeAsBytes(result.binary);
    } else {
      final binFile = File('${dir.path}/$binFileName');
      if (await binFile.exists()) await binFile.delete();
    }
  }

  static Future<SdrlIrDocument?> loadPersistedIr({String? expectedHash}) async {
    final file = File('${(await _sdrlDir()).path}/$irFileName');
    if (!await file.exists()) return null;
    try {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final ir = SdrlIrDocument.fromJson(json);
      if (expectedHash != null &&
          expectedHash.isNotEmpty &&
          ir.sourceHash != expectedHash) {
        return null;
      }
      return ir;
    } catch (_) {
      return null;
    }
  }

  static Future<Directory> _sdrlDir() => SdrlRuleStore.rulesDirectory();

  static SdrlCompileResult? _compileNative(String source) {
    try {
      _ensureNativeBindings();
      final srcPtr = source.toNativeUtf8();
      final outPtr = calloc<Pointer<Utf8>>();
      try {
        final code = _compileJsonFn!(srcPtr, outPtr);
        final jsonPtr = outPtr.value;
        if (jsonPtr == nullptr) {
          return SdrlCompileResult.failure(
            diagnostics: [
              SdrlDiagnostic(
                severity: 'error',
                code: 'E000',
                message: code == 2
                    ? 'Invalid SDRL compile arguments'
                    : 'SDRL compile failed',
              ),
            ],
          );
        }
        final payload = jsonPtr.toDartString();
        _freeFn!(jsonPtr);
        return _parseCompilePayload(payload);
      } finally {
        malloc.free(srcPtr);
        calloc.free(outPtr);
      }
    } catch (e) {
      debugPrint('[SdrlCompiler] native compile unavailable: $e');
      return null;
    }
  }

  static Future<SdrlCompileResult?> _compileViaCli(String source) async {
    try {
      final dir = await getTemporaryDirectory();
      final input = File(
        '${dir.path}/sdrl-build-${DateTime.now().millisecondsSinceEpoch}.sdrl',
      );
      final irOut = File('${input.path}.ir.json');
      final binOut = File('${input.path}.sdrb');
      await input.writeAsString(source);
      final check = await Process.run('sdrlc', [
        'check',
        input.path,
        '--platform',
        'android',
      ]);
      if (check.exitCode != 0) {
        final err = _cliOutput(check);
        return SdrlCompileResult.failure(
          diagnostics: _diagnosticsFromCli(err),
        );
      }
      final build = await Process.run('sdrlc', [
        'build',
        input.path,
        '--output',
        irOut.path,
        '--format',
        'json',
        '--platform',
        'android',
      ]);
      await Process.run('sdrlc', [
        'build',
        input.path,
        '--output',
        binOut.path,
        '--format',
        'bin',
        '--platform',
        'android',
      ]);
      await input.delete().catchError((_) => input);
      if (build.exitCode != 0) {
        return SdrlCompileResult.failure(
          diagnostics: _diagnosticsFromCli(_cliOutput(build)),
        );
      }
      final irJson =
          jsonDecode(await irOut.readAsString()) as Map<String, dynamic>;
      final ir = SdrlIrDocument.fromJson(irJson);
      final binary =
          await binOut.exists() ? await binOut.readAsBytes() : Uint8List(0);
      await irOut.delete().catchError((_) => irOut);
      await binOut.delete().catchError((_) => binOut);
      return SdrlCompileResult.ok(
        ir: ir,
        binary: binary,
        sourceHash: ir.sourceHash,
        diagnostics: ir.warnings,
        ruleCount: ir.rules.length,
      );
    } catch (_) {
      return null;
    }
  }

  static SdrlCompileResult _parseCompilePayload(String payload) {
    final root = jsonDecode(payload) as Map<String, dynamic>;
    final diagnostics = (root['diagnostics'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(SdrlDiagnostic.fromJson)
        .toList();
    final ok = root['ok'] as bool? ?? false;
    if (!ok) {
      return SdrlCompileResult.failure(diagnostics: diagnostics);
    }
    final irJson = root['ir'] as Map<String, dynamic>?;
    final ir = irJson == null ? null : SdrlIrDocument.fromJson(irJson);
    final binaryB64 = root['binary_b64'] as String? ?? '';
    final binary = binaryB64.isEmpty ? Uint8List(0) : base64Decode(binaryB64);
    const maxSdrbBytes = 128 * 1024;
    if (binary.length > maxSdrbBytes) {
      return SdrlCompileResult.failure(
        diagnostics: [
          SdrlDiagnostic(
            severity: 'error',
            code: 'E080',
            message:
                'compiled SDRL-BIN exceeds 128 KiB limit (${binary.length} bytes)',
          ),
        ],
      );
    }
    final sourceHash = root['source_hash'] as String? ?? ir?.sourceHash ?? '';
    return SdrlCompileResult.ok(
      ir: ir,
      binary: binary,
      sourceHash: sourceHash,
      diagnostics: diagnostics,
      ruleCount: ir?.rules.length ?? 0,
    );
  }

  static List<SdrlDiagnostic> _diagnosticsFromCli(String text) {
    if (text.trim().isEmpty) {
      return const [
        SdrlDiagnostic(
          severity: 'error',
          code: 'E000',
          message: 'SDRL validation failed',
        ),
      ];
    }
    return text
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .map(
          (line) => SdrlDiagnostic(
            severity: line.startsWith('warning') ? 'warning' : 'error',
            code:
                RegExp(r'\[([A-Z]\d+)\]').firstMatch(line)?.group(1) ?? 'E000',
            message: line,
          ),
        )
        .toList();
  }

  static String _cliOutput(ProcessResult result) {
    final stderr = result.stderr.toString().trim();
    if (stderr.isNotEmpty) return stderr;
    return result.stdout.toString().trim();
  }

  static void _ensureNativeBindings() {
    _lib ??= _openLib();
    _compileJsonFn ??= _lib!
        .lookup<NativeFunction<SdrlCompileJsonNative>>('sdrl_compile_json')
        .asFunction();
    _freeFn ??=
        _lib!.lookup<NativeFunction<SdrlFreeNative>>('sdrl_free').asFunction();
  }

  static DynamicLibrary _openLib() {
    if (Platform.isAndroid) {
      return DynamicLibrary.open('libsdrl_ffi.so');
    }
    if (Platform.isLinux) {
      for (final path in [
        'libsdrl_ffi.so',
        '../sdrl/target/release/libsdrl_ffi.so',
      ]) {
        try {
          return DynamicLibrary.open(path);
        } catch (_) {}
      }
    }
    if (Platform.isMacOS) {
      return DynamicLibrary.open('libsdrl_ffi.dylib');
    }
    if (Platform.isWindows) {
      return DynamicLibrary.open('sdrl_ffi.dll');
    }
    throw UnsupportedError('platform');
  }
}

typedef SdrlCompileJsonNative = Int32 Function(
  Pointer<Utf8>,
  Pointer<Pointer<Utf8>>,
);
typedef SdrlFreeNative = Void Function(Pointer<Utf8>);

class SdrlCompileResult {
  SdrlCompileResult._({
    required this.ok,
    this.ir,
    Uint8List? binary,
    this.sourceHash = '',
    this.diagnostics = const [],
    this.ruleCount = 0,
  }) : binary = binary ?? Uint8List(0);

  factory SdrlCompileResult.ok({
    required SdrlIrDocument? ir,
    required Uint8List binary,
    required String sourceHash,
    required List<SdrlDiagnostic> diagnostics,
    required int ruleCount,
  }) =>
      SdrlCompileResult._(
        ok: true,
        ir: ir,
        binary: binary,
        sourceHash: sourceHash,
        diagnostics: diagnostics,
        ruleCount: ruleCount,
      );

  factory SdrlCompileResult.failure({
    required List<SdrlDiagnostic> diagnostics,
  }) =>
      SdrlCompileResult._(
        ok: false,
        diagnostics: diagnostics,
      );

  final bool ok;
  final SdrlIrDocument? ir;
  final Uint8List binary;
  final String sourceHash;
  final List<SdrlDiagnostic> diagnostics;
  final int ruleCount;

  List<SdrlDiagnostic> get errors =>
      diagnostics.where((d) => d.isError).toList();

  List<SdrlDiagnostic> get warnings =>
      diagnostics.where((d) => !d.isError).toList();

  String get firstErrorMessage =>
      errors.isNotEmpty ? errors.first.displayLine : 'SDRL compile failed';
}
