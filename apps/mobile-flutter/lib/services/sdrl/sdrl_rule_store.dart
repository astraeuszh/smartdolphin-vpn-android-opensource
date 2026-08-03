import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// User SDRL rules under vpn-core/code/; compiled binaries in code/binary/.
class SdrlRuleStore {
  SdrlRuleStore._();

  static const legacyDotDirName = '.sdrl';
  static const codeDirName = 'code';
  static const extensionDirName = 'SDRL';
  static const binaryDirName = 'binary';
  static const activeBase = 'active';
  static const sdrlExt = '.sdrl';
  static const sdrbExt = '.sdrb';
  static const irFileName = 'active.ir.json';

  static bool _migrated = false;

  static Future<Directory> rulesDirectory() async {
    await _ensureMigrated();
    final dir = await _codeRoot();
    await dir.create(recursive: true);
    await Directory('${dir.path}/$extensionDirName').create(recursive: true);
    await Directory('${dir.path}/$binaryDirName').create(recursive: true);
    return dir;
  }

  static Future<Directory> _vpnCoreRoot() async {
    Directory base;
    if (Platform.isAndroid) {
      base = await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
    } else {
      base = await getApplicationSupportDirectory();
    }
    final root = Directory('${base.path}/vpn-core');
    await root.create(recursive: true);
    return root;
  }

  static Future<Directory> _codeRoot() async {
    final root = await _vpnCoreRoot();
    return Directory('${root.path}/$codeDirName');
  }

  static Future<void> _ensureMigrated() async {
    if (_migrated) return;
    _migrated = true;
    try {
      final core = await _vpnCoreRoot();
      final legacy = Directory('${core.path}/$legacyDotDirName');
      if (!await legacy.exists()) return;
      final target = await _codeRoot();
      await target.create(recursive: true);
      await Directory('${target.path}/$binaryDirName').create(recursive: true);
      await for (final entity in legacy.list()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (name.endsWith(sdrbExt)) {
          await entity.copy('${target.path}/$binaryDirName/$name');
        } else {
          await entity.copy('${target.path}/$name');
        }
      }
    } catch (_) {}
  }

  static String sanitizeFileName(String raw) {
    var name = raw.trim();
    if (name.endsWith(sdrlExt)) {
      name = name.substring(0, name.length - sdrlExt.length);
    }
    name = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    name = name.replaceAll(RegExp(r'\s+'), '_');
    if (name.isEmpty) name = 'rule';
    return name;
  }

  static String tempName() => 'temp_${DateTime.now().millisecondsSinceEpoch}';

  static Future<List<SdrlSavedRule>> listSavedRules() async {
    final dir = await rulesDirectory();
    final entries = <SdrlSavedRule>[];
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      if (!entity.path.endsWith(sdrlExt)) continue;
      final base = entity.uri.pathSegments.last.replaceAll(sdrlExt, '');
      if (base == activeBase || base.startsWith('temp_')) continue;
      final stat = await entity.stat();
      entries.add(SdrlSavedRule(name: base, modified: stat.modified));
    }
    entries.sort((a, b) => b.modified.compareTo(a.modified));
    return entries;
  }

  static Future<void> saveNamedRule({
    required String displayName,
    required String source,
    required Uint8List binary,
    required String sourceHash,
  }) async {
    final name = sanitizeFileName(displayName);
    final dir = await rulesDirectory();
    await File('${dir.path}/$name$sdrlExt').writeAsString(source);
    final sdrb = File('${dir.path}/$binaryDirName/$name$sdrbExt');
    if (binary.isEmpty) {
      if (await sdrb.exists()) await sdrb.delete();
    } else {
      await sdrb.writeAsBytes(binary);
    }
    await _writeActiveFromNamed(name, source, binary, sourceHash);
  }

  static Future<void> _writeActiveFromNamed(
    String name,
    String source,
    Uint8List binary,
    String sourceHash,
  ) async {
    final dir = await rulesDirectory();
    await File('${dir.path}/$activeBase$sdrlExt').writeAsString(source);
    final activeBin = File('${dir.path}/$binaryDirName/$activeBase$sdrbExt');
    if (binary.isEmpty) {
      if (await activeBin.exists()) await activeBin.delete();
    } else {
      await activeBin.writeAsBytes(binary);
    }
    await File('${dir.path}/$irFileName').writeAsString(
      jsonEncode({
        'saved_name': name,
        'source_hash': sourceHash,
        'updated_at': DateTime.now().toIso8601String(),
      }),
    );
  }

  static Future<String?> loadActiveSource() async {
    final file = File('${(await rulesDirectory()).path}/$activeBase$sdrlExt');
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  static Future<bool> activateNamedRule(String displayName) async {
    final name = sanitizeFileName(displayName);
    final dir = await rulesDirectory();
    final srcFile = File('${dir.path}/$name$sdrlExt');
    if (!await srcFile.exists()) return false;
    final source = await srcFile.readAsString();
    final namedBin = File('${dir.path}/$binaryDirName/$name$sdrbExt');
    Uint8List binary = Uint8List(0);
    if (await namedBin.exists()) {
      binary = await namedBin.readAsBytes();
    }
    await _writeActiveFromNamed(name, source, binary, '');
    return true;
  }

  static Future<String?> loadNamedSource(String displayName) async {
    final name = sanitizeFileName(displayName);
    final file = File('${(await rulesDirectory()).path}/$name$sdrlExt');
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  static Future<void> deleteNamedRule(String displayName) async {
    final name = sanitizeFileName(displayName);
    final dir = await rulesDirectory();
    final sdrl = File('${dir.path}/$name$sdrlExt');
    if (await sdrl.exists()) await sdrl.delete();
    final sdrb = File('${dir.path}/$binaryDirName/$name$sdrbExt');
    if (await sdrb.exists()) await sdrb.delete();
  }
}

class SdrlSavedRule {
  const SdrlSavedRule({required this.name, required this.modified});

  final String name;
  final DateTime modified;
}
