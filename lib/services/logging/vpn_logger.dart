import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../features/settings/domain/log_config.dart';
import '../../features/settings/domain/settings_controller.dart';

/// User-managed opera logs + system/error logs + in-memory cache when disabled.
class VpnLogger {
  VpnLogger(this._getLogConfig);

  final LogConfig Function() _getLogConfig;
  File? _logFile;
  String? _logDir;
  int _currentSize = 0;
  final List<String> _memoryCache = [];
  static const _memoryCacheMaxLines = 256;

  static String _formatLine(String level, String message) {
    final time = DateTime.now().toIso8601String();
    return '[$time] [$level] $message\n';
  }

  Future<String?> _ensureLogDir() async {
    if (_logDir != null) return _logDir;
    try {
      final dir = await getApplicationSupportDirectory();
      final logsDir = Directory('${dir.path}/logs');
      if (!await logsDir.exists()) {
        await logsDir.create(recursive: true);
      }
      _logDir = logsDir.path;
      return _logDir;
    } catch (e) {
      debugPrint('[VpnLogger] Failed to get log dir: $e');
      return null;
    }
  }

  void _pushCache(String line) {
    _memoryCache.add(line);
    if (_memoryCache.length > _memoryCacheMaxLines) {
      _memoryCache.removeAt(0);
    }
  }

  Future<File?> _ensureUserLogFile() async {
    final config = _getLogConfig();
    if (!config.enabled) return null;

    final dir = await _ensureLogDir();
    if (dir == null) return null;

    final path = '$dir/opera.log';
    _logFile ??= File(path);
    if (!await _logFile!.exists()) {
      _currentSize = 0;
    } else {
      _currentSize = await _logFile!.length();
    }
    return _logFile;
  }

  Future<void> _rotateIfNeeded() async {
    final config = _getLogConfig();
    final maxBytes = config.sizeLimitMb * 1024 * 1024;
    if (_currentSize < maxBytes) return;

    final dir = await _ensureLogDir();
    if (dir == null) return;

    for (var i = config.countLimit - 1; i >= 0; i--) {
      final src = i == 0 ? File('$dir/opera.log') : File('$dir/opera.$i.log');
      final dst = File('$dir/opera.${i + 1}.log');
      if (await dst.exists()) await dst.delete();
      if (await src.exists()) await src.rename(dst.path);
    }
    _logFile = File('$dir/opera.log');
    _currentSize = 0;
  }

  Future<void> _appendUser(String level, String message) async {
    final line = _formatLine(level, message);
    final config = _getLogConfig();
    if (!config.enabled) {
      _pushCache(line);
      return;
    }

    switch (level) {
      case 'debug':
        if (!config.shouldLogDebug) return;
        break;
      case 'info':
        if (!config.shouldLogInfo) return;
        break;
      case 'warn':
        if (!config.shouldLogWarn) return;
        break;
      case 'error':
        if (!config.shouldLogError) return;
        break;
    }

    final file = await _ensureUserLogFile();
    if (file == null) {
      _pushCache(line);
      return;
    }

    await _rotateIfNeeded();
    try {
      await file.writeAsString(line, mode: FileMode.append);
      _currentSize += line.length;
    } catch (e) {
      debugPrint('[VpnLogger] Write failed: $e');
    }
  }

  Future<void> _appendSystem(String level, String message) async {
    final dir = await _ensureLogDir();
    if (dir == null) return;
    final file = File('$dir/system.log');
    try {
      await file.writeAsString(_formatLine(level, message), mode: FileMode.append);
    } catch (e) {
      debugPrint('[VpnLogger] System write failed: $e');
    }
  }

  void debug(String message) {
    debugPrint('[VpnLogger] $message');
    unawaited(_appendUser('debug', message));
  }

  void info(String message) {
    debugPrint('[VpnLogger] $message');
    unawaited(_appendUser('info', message));
  }

  void warn(String message) {
    debugPrint('[VpnLogger] $message');
    unawaited(_appendUser('warn', message));
  }

  void error(String message) {
    debugPrint('[VpnLogger] $message');
    unawaited(_appendUser('error', message));
    unawaited(_appendSystem('error', message));
  }

  void system(String message) {
    unawaited(_appendSystem('info', message));
  }

  Future<String> buildFeedbackSnapshot({int maxChars = 32000}) async {
    final buf = StringBuffer();
    if (_memoryCache.isNotEmpty) {
      buf.write('--- memory cache ---\n');
      buf.write(_memoryCache.join());
    }
    final dir = await _ensureLogDir();
    if (dir != null) {
      for (final name in ['system.log', 'opera.log', 'vpn.log']) {
        final file = File('$dir/$name');
        if (await file.exists()) {
          buf.write('--- $name ---\n');
          try {
            final text = await file.readAsString();
            buf.write(text.length > 8000 ? text.substring(text.length - 8000) : text);
          } catch (_) {}
        }
      }
    }
    final out = buf.toString();
    if (out.length <= maxChars) return out;
    return out.substring(out.length - maxChars);
  }

  Future<int> estimateFeedbackSnapshotBytes({int maxChars = 32000}) async {
    final snapshot = await buildFeedbackSnapshot(maxChars: maxChars);
    return snapshot.codeUnits.length;
  }

  Future<void> clearLogs() async {
    final dir = await _ensureLogDir();
    if (dir == null) return;

    try {
      final logs = Directory(dir);
      await for (final entity in logs.list()) {
        if (entity is! File) continue;
        final name = entity.path.split('/').last;
        if (name.startsWith('opera') || name == 'vpn.log') {
          await entity.delete();
        }
      }
      _logFile = null;
      _currentSize = 0;
      _memoryCache.clear();
    } catch (e) {
      debugPrint('[VpnLogger] Clear failed: $e');
    }
  }

  Future<String?> get logDirectory async => _ensureLogDir();
}

final vpnLoggerProvider = Provider<VpnLogger>((ref) {
  return VpnLogger(() => ref.read(settingsControllerProvider).logConfig);
});
