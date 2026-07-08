import 'dart:async';

import '../../features/speedtest/domain/speedtest_state.dart';
import '../vpn/clash_api_client.dart';
import 'ndt7_models.dart';
import 'ndt7_service.dart';

/// M-Lab NDT7 (Measurement Lab / MIT) — traffic follows the active network route.
class SpeedTestService {
  SpeedTestService({Ndt7Service? ndt7}) : _ndt7 = ndt7 ?? Ndt7Service();

  final Ndt7Service _ndt7;
  var _cancelled = false;

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
        onError(error.message);
      }
    } on Object catch (error) {
      if (!_cancelled) {
        onError(error.toString());
      }
    } finally {
      await progressSub?.cancel();
    }
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
