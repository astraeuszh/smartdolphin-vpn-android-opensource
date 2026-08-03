import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../features/settings/domain/log_config.dart';
import '../../features/settings/domain/settings_controller.dart';
import 'vpn_core_layout.dart';

/// vpn-core logging: system logs are protected; optional local logs are bounded
/// by the user's configured retention limits.
class VpnLogger {
  VpnLogger(this._getLogConfig);

  final LogConfig Function() _getLogConfig;
  VpnCoreLayout? _layout;
  final Map<String, DateTime> _dedup = {};
  DateTime? _lastCapCheck;
  static const _dedupWindow = Duration(seconds: 5);
  final List<String> _memoryCache = [];
  static const _memoryCacheMaxLines = 4096;
  static final RegExp _lineTimestamp =
      RegExp(r'(\d{4}-\d{2}-\d{2}T[\d:.]+(?:Z|[+-]\d{2}:\d{2})?)');

  static String _formatLine(String level, String component, String message) {
    final time = DateTime.now().toIso8601String();
    return '$level $time ${component.padRight(12)} $message\n';
  }

  /// External app-specific storage (no root required). Typical path:
  /// `/storage/emulated/0/Android/data/<pkg>/files/vpn-core`
  Future<VpnCoreLayout> layout() async {
    if (_layout != null) return _layout!;
    Directory base;
    if (Platform.isAndroid) {
      base = await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
    } else {
      base = await getApplicationSupportDirectory();
    }
    final root = Directory('${base.path}/vpn-core');
    final lay = VpnCoreLayout(root.path);
    for (final rel in VpnCoreLayout.initDirs) {
      await Directory('${root.path}/$rel').create(recursive: true);
    }
    // Remove the obsolete high-volume debug stream from older builds.
    final legacyDebug = Directory('${root.path}/logs/debug');
    if (await legacyDebug.exists()) {
      await legacyDebug.delete(recursive: true);
    }
    await File('${lay.logs}/README.txt').writeAsString(
      'Smart Dolphin VPN logs (vpn-core)\n'
      'System logs under logs/; open this folder from a file manager.\n'
      'Path: ${root.path}\n',
    );
    _layout = lay;
    return lay;
  }

  Future<String?> get logDirectory async {
    final lay = await layout();
    return lay.root;
  }

  bool _skipDedup(String key) {
    final now = DateTime.now();
    final prev = _dedup[key];
    if (prev != null && now.difference(prev) < _dedupWindow) {
      return true;
    }
    _dedup[key] = now;
    return false;
  }

  void _pushCache(String line) {
    _memoryCache.add(line);
    if (_memoryCache.length > _memoryCacheMaxLines) {
      _memoryCache.removeAt(0);
    }
  }

  Future<void> _append(String category, String file, String level,
      String component, String message) async {
    final line = _formatLine(level, component, message);
    final config = _getLogConfig();
    // Logging off means privacy-minimal operation: only explicit errors and
    // service-essential records survive. Normal connection/auth telemetry is
    // diagnostic data and must remain opt-in.
    if (!config.enabled && category != 'logs/system' && level != 'ERROR') {
      return;
    }
    final lay = await layout();
    final path = lay.logFile(category, file);
    try {
      final f = File(path);
      await f.parent.create(recursive: true);
      await f.writeAsString(line, mode: FileMode.append);
      if (category == 'logs/user') {
        await _enforceUserCap(lay);
      }
    } catch (e) {
      debugPrint('[VpnLogger] write failed: $e');
      _pushCache(line);
    }
  }

  Future<void> _enforceUserCap(VpnCoreLayout lay) async {
    final now = DateTime.now();
    if (_lastCapCheck != null &&
        now.difference(_lastCapCheck!) < const Duration(minutes: 1)) {
      return;
    }
    _lastCapCheck = now;
    final config = _getLogConfig();
    final maxBytes = config.sizeLimitMb * 1024 * 1024;
    final maxFiles = config.countLimit;
    final files = <File>[];
    var total = 0;
    for (final cat in VpnCoreLayout.userCategories) {
      final dir = Directory(lay.logFile(cat, ''));
      if (!await dir.exists()) continue;
      await for (final entity in dir.list()) {
        if (entity is! File || !entity.path.endsWith('.log')) continue;
        final len = await entity.length();
        files.add(entity);
        total += len;
      }
    }
    files.sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));
    while (files.length > maxFiles || total > maxBytes) {
      if (files.isEmpty) break;
      final oldest = files.removeAt(0);
      total -= await oldest.length();
      await oldest.delete();
    }
  }

  void debug(String message, {String component = 'app'}) {
    debugPrint('[VpnLogger] $message');
  }

  void info(String message, {String component = 'app'}) {
    debugPrint('[VpnLogger] $message');
    unawaited(
        _append('logs/runtime', 'runtime.log', 'INFO', component, message));
  }

  void warn(String message, {String component = 'app'}) {
    debugPrint('[VpnLogger] $message');
    unawaited(
        _append('logs/runtime', 'runtime.log', 'WARN', component, message));
  }

  void error(String message, {String component = 'app'}) {
    debugPrint('[VpnLogger] $message');
    unawaited(
        _append('logs/runtime', 'runtime.log', 'ERROR', component, message));
    unawaited(_writeCrashMeta(component, message));
  }

  void system(String message, {String component = 'service'}) {
    unawaited(
        _append('logs/system', 'service.log', 'INFO', component, message));
  }

  void userAction(String action, String status, String message) {
    if (!_getLogConfig().enabled) return;
    unawaited(_append(
        'logs/user', 'action.log', 'INFO', action, '$status | $message'));
  }

  void network(String component, String message) {
    final key = 'net:$component:$message';
    if (_skipDedup(key)) return;
    unawaited(
        _append('logs/network', 'connect.log', 'INFO', component, message));
  }

  void auth(String component, String message) {
    final key = 'auth:$component:$message';
    if (_skipDedup(key)) return;
    unawaited(_append('logs/security', 'auth.log', 'INFO', component, message));
  }

  Future<void> _writeCrashMeta(String component, String message) async {
    final lay = await layout();
    final f = File('${lay.crash}/crash_meta.json');
    await f.writeAsString(
      '{"time":"${DateTime.now().toIso8601String()}","component":"$component","message":${_jsonQuote(message)}}\n',
    );
  }

  String _jsonQuote(String s) {
    return '"${s.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';
  }

  DateTime? _parseLineTime(String line) {
    final match = _lineTimestamp.firstMatch(line);
    if (match == null) return null;
    return DateTime.tryParse(match.group(1)!);
  }

  bool _withinWindow(String line, DateTime cutoff, {required bool isHeader}) {
    if (isHeader) return true;
    final ts = _parseLineTime(line);
    if (ts == null) return true;
    return !ts.isBefore(cutoff);
  }

  /// Collects all log lines within [window] before now (not a fixed line count).
  Future<String> buildFeedbackSnapshot({
    Duration window = VpnCoreLayout.defaultFeedbackWindow,
  }) async {
    final cutoff = DateTime.now().subtract(window);
    final buf = StringBuffer()
      ..writeln(
        '=== feedback log window: last ${window.inMinutes} min (since ${cutoff.toIso8601String()}) ===',
      );
    var lineCount = 0;

    if (_memoryCache.isNotEmpty) {
      buf.writeln('=== memory cache ===');
      for (final ln in _memoryCache) {
        final trimmed = ln.trimRight();
        if (trimmed.isEmpty) continue;
        if (!_withinWindow(trimmed, cutoff, isHeader: false)) continue;
        buf.writeln(trimmed);
        lineCount++;
      }
    }

    final lay = await layout();
    for (final rel in VpnCoreLayout.feedbackPriority) {
      final parts = rel.split('/');
      final file = parts.removeLast();
      final category = parts.join('/');
      final path = lay.logFile(category, file);
      final f = File(path);
      if (!await f.exists()) continue;
      buf.writeln('=== $rel ===');
      try {
        final lines = await f.readAsLines();
        for (final ln in lines) {
          if (ln.trim().isEmpty) continue;
          if (!_withinWindow(ln, cutoff, isHeader: ln.startsWith('==='))) {
            continue;
          }
          buf.writeln(ln);
          lineCount++;
        }
      } catch (_) {}
    }

    buf.writeln('=== total lines in window: $lineCount ===');
    return _redact(buf.toString());
  }

  Future<String> buildErrorFeedbackSnapshot() => buildFeedbackSnapshot(
        window: VpnCoreLayout.errorFeedbackWindow,
      );

  Future<int> estimateFeedbackSnapshotBytes({
    Duration window = VpnCoreLayout.defaultFeedbackWindow,
  }) async {
    final snapshot = await buildFeedbackSnapshot(window: window);
    return snapshot.codeUnits.length;
  }

  String _redact(String s) {
    const keys = ['password=', 'session_token', 'authorization:', 'bearer '];
    return s.split('\n').map((line) {
      final low = line.toLowerCase();
      for (final k in keys) {
        if (low.contains(k)) return '[redacted]';
      }
      return line;
    }).join('\n');
  }

  Future<void> clearUserLogs() async {
    final lay = await layout();
    for (final cat in VpnCoreLayout.userCategories) {
      final dir = Directory(lay.logFile(cat, ''));
      if (!await dir.exists()) continue;
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.log')) {
          await entity.delete();
        }
      }
    }
    for (final cat in const [
      'logs/network',
      'logs/security',
      'logs/audit',
      'logs/telemetry',
    ]) {
      final dir = Directory(lay.logFile(cat, ''));
      if (!await dir.exists()) continue;
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.log')) {
          await entity.delete();
        }
      }
    }
    final runtime = Directory(lay.logFile('logs/runtime', ''));
    if (await runtime.exists()) {
      await for (final entity in runtime.list()) {
        if (entity is! File || !entity.path.endsWith('.log')) continue;
        try {
          final errors = (await entity.readAsLines())
              .where((line) => line.startsWith('ERROR '))
              .join('\n');
          await entity.writeAsString(errors.isEmpty ? '' : '$errors\n');
        } catch (_) {}
      }
    }
    _memoryCache.clear();
  }
}

final vpnLoggerProvider = Provider<VpnLogger>((ref) {
  return VpnLogger(() => ref.read(settingsControllerProvider).logConfig);
});
