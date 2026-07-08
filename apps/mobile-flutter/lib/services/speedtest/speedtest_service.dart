import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../features/speedtest/domain/speedtest_state.dart';
import '../vpn/clash_api_client.dart';
import 'ndt7_models.dart';
import 'ndt7_service.dart';

/// M-Lab NDT7 (Measurement Lab / MIT) — traffic follows the active network route.
class SpeedTestService {
  SpeedTestService({Ndt7Service? ndt7, http.Client? client})
      : _ndt7 = ndt7 ?? Ndt7Service(),
        _client = client ?? http.Client();

  final Ndt7Service _ndt7;
  final http.Client _client;
  var _cancelled = false;

  static final _fallbackDownloadEndpoints = <Uri>[
    Uri.parse('https://speed.cloudflare.com/__down?bytes=12582912'),
    Uri.parse('https://cachefly.cachefly.net/10mb.test'),
    Uri.parse('https://proof.ovh.net/files/10Mb.dat'),
  ];

  static final _fallbackPingEndpoints = <Uri>[
    Uri.parse('https://speed.cloudflare.com/__down?bytes=1'),
    Uri.parse('https://cachefly.cachefly.net/1mb.test'),
    Uri.parse('https://www.gstatic.com/generate_204'),
  ];

  Future<void> runTest({
    required bool measureThroughVpn,
    required void Function(SpeedTestPhase phase) onPhase,
    required void Function(String serverName) onServerSelected,
    required void Function(int pingMs) onPingSample,
    required void Function(double mbps, double progress) onDownloadProgress,
    required void Function(double mbps, double progress) onUploadProgress,
    required void Function(String message) onError,
    required void Function({
      required double downloadMbps,
      required double uploadMbps,
      required int pingMs,
    }) onCompleted,
  }) async {
    _cancelled = false;
    StreamSubscription<Ndt7Progress>? progressSub;

    try {
      onPhase(SpeedTestPhase.locating);
      progressSub = _ndt7.progressStream.listen((progress) {
        if (_cancelled) return;
        switch (progress.phase) {
          case Ndt7ProgressPhase.locating:
            onPhase(SpeedTestPhase.locating);
          case Ndt7ProgressPhase.downloadWarmup:
          case Ndt7ProgressPhase.download:
            onPhase(SpeedTestPhase.download);
            if (progress.mbps != null) {
              onDownloadProgress(progress.mbps!, 0);
            }
          case Ndt7ProgressPhase.uploadWarmup:
          case Ndt7ProgressPhase.upload:
            onPhase(SpeedTestPhase.upload);
            if (progress.mbps != null) {
              onUploadProgress(progress.mbps!, 0);
            }
          case Ndt7ProgressPhase.complete:
          case Ndt7ProgressPhase.idle:
          case Ndt7ProgressPhase.error:
            break;
        }
      });

      final summary = await _ndt7.runTest(
        warmup: const Duration(seconds: 3),
        measure: const Duration(seconds: 10),
      );
      if (_cancelled) return;

      final serverLabel = _serverLabel(summary);
      onServerSelected(serverLabel);

      // NDT7 MinRTT comes from TCP_INFO on the local segment — single-digit ms
      // even over VPN. When testing through the tunnel, use Clash proxy delay.
      var pingMs = summary.minRttMs?.round() ?? 0;
      if (measureThroughVpn) {
        final tunnelMs = await ClashApiClient.proxyDelayMs(timeoutMs: 8000);
        if (tunnelMs != null && tunnelMs > 0) {
          pingMs = tunnelMs;
        }
      }
      if (pingMs > 0) {
        onPhase(SpeedTestPhase.ping);
        onPingSample(pingMs);
      }

      onCompleted(
        downloadMbps: summary.downloadMbps,
        uploadMbps: summary.uploadMbps,
        pingMs: pingMs,
      );
    } on Ndt7Exception catch (error) {
      if (!_cancelled) {
        try {
          await _runHttpsFallback(
            measureThroughVpn: measureThroughVpn,
            onPhase: onPhase,
            onServerSelected: onServerSelected,
            onPingSample: onPingSample,
            onDownloadProgress: onDownloadProgress,
            onUploadProgress: onUploadProgress,
            onCompleted: onCompleted,
          );
        } catch (_) {
          onError(error.message);
        }
      }
    } on Object catch (error) {
      if (!_cancelled) {
        onError(error.toString());
      }
    } finally {
      await progressSub?.cancel();
    }
  }

  Future<void> _runHttpsFallback({
    required bool measureThroughVpn,
    required void Function(SpeedTestPhase phase) onPhase,
    required void Function(String serverName) onServerSelected,
    required void Function(int pingMs) onPingSample,
    required void Function(double mbps, double progress) onDownloadProgress,
    required void Function(double mbps, double progress) onUploadProgress,
    required void Function({
      required double downloadMbps,
      required double uploadMbps,
      required int pingMs,
    }) onCompleted,
  }) async {
    onServerSelected('HTTPS multi-endpoint fallback');
    onPhase(SpeedTestPhase.ping);
    final pingMs = await _httpsPingMs();
    if (!_cancelled && pingMs > 0) onPingSample(pingMs);

    onPhase(SpeedTestPhase.download);
    final downloadMbps = await _measureDownload(onDownloadProgress);

    onPhase(SpeedTestPhase.upload);
    final uploadMbps = await _measureUpload(onUploadProgress);

    var finalPing = pingMs;
    if (measureThroughVpn) {
      final tunnelMs = await ClashApiClient.proxyDelayMs(timeoutMs: 8000);
      if (tunnelMs != null && tunnelMs > 0) finalPing = tunnelMs;
    }

    if (_cancelled) return;
    onCompleted(
      downloadMbps: downloadMbps,
      uploadMbps: uploadMbps,
      pingMs: finalPing,
    );
  }

  Future<int> _httpsPingMs() async {
    final samples = <int>[];
    for (final uri in _fallbackPingEndpoints) {
      if (_cancelled) break;
      try {
        final sw = Stopwatch()..start();
        final request = http.Request('HEAD', uri);
        final response =
            await _client.send(request).timeout(const Duration(seconds: 4));
        await response.stream.drain<void>();
        sw.stop();
        if (response.statusCode < 500 && sw.elapsedMilliseconds > 0) {
          samples.add(sw.elapsedMilliseconds);
        }
      } catch (_) {}
    }
    if (samples.isEmpty) return 0;
    samples.sort();
    return samples[samples.length ~/ 2];
  }

  Future<double> _measureDownload(
    void Function(double mbps, double progress) onProgress,
  ) async {
    final samples = <double>[];
    for (final uri in _fallbackDownloadEndpoints) {
      if (_cancelled) break;
      try {
        final sample = await _measureSingleDownload(uri, onProgress);
        if (_isPlausibleMbps(sample)) samples.add(sample);
        if (samples.length >= 2) break;
      } catch (_) {}
    }
    return _stableMbps(samples);
  }

  Future<double> _measureSingleDownload(
    Uri uri,
    void Function(double mbps, double progress) onProgress,
  ) async {
    final request = http.Request('GET', uri);
    final response =
        await _client.send(request).timeout(const Duration(seconds: 8));
    if (response.statusCode < 200 || response.statusCode >= 500) return 0;
    final declaredLength = response.contentLength;
    final totalBytes = declaredLength != null && declaredLength > 0
        ? declaredLength
        : 10 * 1024 * 1024;
    var received = 0;
    final sw = Stopwatch()..start();
    await for (final chunk
        in response.stream.timeout(const Duration(seconds: 12))) {
      if (_cancelled) break;
      received += chunk.length;
      final seconds = max(sw.elapsedMilliseconds / 1000.0, 0.25);
      final mbps = _clampMbps((received * 8) / seconds / 1000000);
      onProgress(mbps, (received / totalBytes).clamp(0, 1).toDouble());
      if (sw.elapsed >= const Duration(seconds: 8) &&
          received >= 2 * 1024 * 1024) {
        break;
      }
    }
    sw.stop();
    if (received < 256 * 1024) return 0;
    final seconds = max(sw.elapsedMilliseconds / 1000.0, 0.25);
    return _clampMbps((received * 8) / seconds / 1000000);
  }

  Future<double> _measureUpload(
    void Function(double mbps, double progress) onProgress,
  ) async {
    const totalBytes = 1024 * 1024;
    final payload = Uint8List(totalBytes);
    final random = Random(7);
    for (var i = 0; i < payload.length; i++) {
      payload[i] = random.nextInt(256);
    }
    final sw = Stopwatch()..start();
    try {
      final response = await _client
          .post(
            Uri.parse('https://speed.cloudflare.com/__up'),
            body: payload,
          )
          .timeout(const Duration(seconds: 10));
      sw.stop();
      if (response.statusCode < 200 || response.statusCode >= 500) return 0;
      final seconds = max(sw.elapsedMilliseconds / 1000.0, 0.1);
      final mbps = _clampMbps((totalBytes * 8) / seconds / 1000000);
      onProgress(mbps, 1);
      return mbps;
    } catch (_) {
      return 0;
    }
  }

  bool _isPlausibleMbps(double value) =>
      value.isFinite && value >= 0.05 && value <= 1500;

  double _clampMbps(double value) {
    if (!_isPlausibleMbps(value)) return 0;
    return value;
  }

  double _stableMbps(List<double> values) {
    final filtered = values.where(_isPlausibleMbps).toList()..sort();
    if (filtered.isEmpty) return 0;
    if (filtered.length == 1) return filtered.first;
    return filtered[filtered.length ~/ 2];
  }

  String _serverLabel(TestSummary summary) {
    final city = summary.serverCity.trim();
    final country = summary.serverCountry.trim();
    if (city.isNotEmpty && country.isNotEmpty) {
      return 'M-Lab • $city, $country';
    }
    if (country.isNotEmpty) {
      return 'M-Lab • $country';
    }
    return 'M-Lab NDT7';
  }

  bool get isTestInProgress => false;

  Future<bool> cancelTest() async {
    _cancelled = true;
    return true;
  }
}
