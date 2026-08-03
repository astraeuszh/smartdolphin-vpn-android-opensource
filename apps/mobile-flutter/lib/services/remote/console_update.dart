import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../platform/android/voice_recorder_channel.dart';
import 'console_endpoint.dart';

class UpdateCheckResult {
  const UpdateCheckResult({
    required this.versionName,
    required this.versionCode,
    required this.releaseNotes,
    required this.apkUrl,
    required this.forceUpdate,
    required this.published,
    required this.sha256,
    required this.packageSize,
    required this.downloadUrls,
    required this.chunkManifestUrl,
    required this.minimumSupportedVersion,
    required this.minimumSupportedBuild,
  });

  final String versionName;
  final int versionCode;
  final String releaseNotes;
  final String apkUrl;
  final bool forceUpdate;
  final bool published;
  final String sha256;
  final int packageSize;
  final List<String> downloadUrls;
  final String chunkManifestUrl;
  final String minimumSupportedVersion;
  final int minimumSupportedBuild;

  String get minimumVersion => minimumSupportedVersion;

  bool isNewerThan({
    required String currentVersion,
    required String currentBuild,
  }) {
    if (!published) return false;

    final installedVersionCode = int.tryParse(currentBuild.trim());
    if (installedVersionCode != null && versionCode > 0) {
      // Android refuses to replace an installed package with a lower or equal
      // versionCode, even if versionName looks newer.
      return versionCode > installedVersionCode;
    }
    return _compareVersions(versionName, currentVersion) > 0;
  }

  static int _compareVersions(String left, String right) {
    final a = left.split('.').map((part) => int.tryParse(part) ?? 0).toList();
    final b = right.split('.').map((part) => int.tryParse(part) ?? 0).toList();
    final length = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < length; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x != y) return x > y ? 1 : -1;
    }
    return 0;
  }
}

class ConsoleUpdate {
  ConsoleUpdate({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const _native = MethodChannel('smartdolphin/update');
  static const int _maximumApkBytes = 1024 * 1024 * 1024;

  Future<void> enqueueBackground(UpdateCheckResult update) async {
    await _native.invokeMethod<int>('enqueue', {
      'versionName': update.versionName,
      'versionCode': update.versionCode,
      'url': update.apkUrl,
      'sha256': update.sha256,
      'size': update.packageSize,
      'downloadUrls': update.downloadUrls,
      'chunkManifestUrl': update.chunkManifestUrl,
    });
  }

  Future<({String status, int received, int total})> backgroundState() async {
    final value =
        await _native.invokeMapMethod<String, dynamic>('state') ?? const {};
    return (
      status: value['status']?.toString() ?? 'idle',
      received: (value['received'] as num?)?.toInt() ?? 0,
      total: (value['total'] as num?)?.toInt() ?? 0,
    );
  }

  Future<bool> openBackgroundInstaller() async =>
      await _native.invokeMethod<bool>('install') ?? false;

  Future<UpdateCheckResult> check({
    required String version,
    required String build,
  }) async {
    final response = await _client
        .get(Uri.parse('${ConsoleEndpoint.base}/api/auth/android-version'))
        .timeout(const Duration(seconds: 12));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Update service unavailable');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (body['ok'] != true) throw StateError('Invalid update response');
    final installedBuild = int.tryParse(build.trim()) ?? 0;
    final minimumSupportedBuild =
        (body['minimum_supported_build'] as num?)?.toInt() ?? 0;
    final belowMandatoryFloor = minimumSupportedBuild > 0 &&
        installedBuild > 0 &&
        installedBuild < minimumSupportedBuild;
    return UpdateCheckResult(
      versionName: (body['version_name'] as String?)?.trim() ?? version,
      versionCode:
          (body['version_code'] as num?)?.toInt() ?? (int.tryParse(build) ?? 0),
      releaseNotes: (body['release_notes'] as String?)?.trim() ?? '',
      apkUrl: (body['apk_url'] as String?)?.trim() ?? '',
      // A release can be optional for supported clients while remaining
      // mandatory for clients below the service floor. Do not bind those two
      // independent policies to the latest release's force_update flag.
      forceUpdate: body['force_update'] == true || belowMandatoryFloor,
      published: body['published'] == true,
      sha256: (body['sha256'] as String?)?.trim().toLowerCase() ?? '',
      packageSize: (body['package_size'] as num?)?.toInt() ?? 0,
      downloadUrls: (body['download_urls'] as List<dynamic>?)
              ?.map((value) => value.toString())
              .where((value) => value.startsWith('https://'))
              .toList() ??
          const [],
      chunkManifestUrl: (body['chunk_manifest_url'] as String?)?.trim() ?? '',
      minimumSupportedVersion:
          (body['minimum_supported_version'] as String?)?.trim() ?? '',
      minimumSupportedBuild: minimumSupportedBuild,
    );
  }

  Future<void> downloadAndInstall(
    UpdateCheckResult update, {
    void Function(int received, int total)? onProgress,
  }) async {
    final parsed = Uri.tryParse(update.apkUrl);
    if (parsed == null) {
      throw StateError('Invalid APK URL');
    }
    final uri = parsed.hasScheme
        ? parsed
        : Uri.parse('https://smartdolphinvpn.com').resolveUri(parsed);
    final directory = await getTemporaryDirectory();
    final apk =
        File('${directory.path}/SmartDolphinVPN-${update.versionName}.apk');
    final request = http.Request('GET', uri);
    final response =
        await _client.send(request).timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('APK download failed');
    }
    try {
      final responseLength = response.contentLength;
      if (responseLength != null && responseLength > _maximumApkBytes) {
        throw StateError('APK package is too large');
      }
      if (update.packageSize > _maximumApkBytes) {
        throw StateError('APK package is too large');
      }
      if (responseLength != null &&
          update.packageSize > 0 &&
          responseLength != update.packageSize) {
        throw StateError('APK package size does not match the manifest');
      }
      final expectedLength =
          update.packageSize > 0 ? update.packageSize : responseLength ?? 0;
      var received = 0;
      final sink = apk.openWrite();
      try {
        await for (final chunk
            in response.stream.timeout(const Duration(minutes: 10))) {
          received += chunk.length;
          if (received > _maximumApkBytes ||
              (expectedLength > 0 && received > expectedLength)) {
            throw StateError('APK package is too large');
          }
          sink.add(chunk);
          onProgress?.call(received, expectedLength);
        }
      } finally {
        await sink.close();
      }
      if (expectedLength > 0 && received != expectedLength) {
        throw StateError('APK download is incomplete');
      }
      if (update.sha256.isNotEmpty) {
        // The platform-default HashSink may buffer all chunks. The pure Dart
        // implementation incrementally consumes them and keeps memory bounded.
        final hashSink = Sha256().toSync().newHashSink();
        await for (final chunk in apk.openRead()) {
          hashSink.add(chunk);
        }
        hashSink.close();
        final digest = await hashSink.hash();
        final actual = digest.bytes
            .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
            .join();
        if (actual != update.sha256) {
          throw StateError('APK verification failed');
        }
      }
    } catch (_) {
      if (await apk.exists()) await apk.delete();
      rethrow;
    }
    await VoiceRecorderChannel.openMedia(apk.path);
  }
}
