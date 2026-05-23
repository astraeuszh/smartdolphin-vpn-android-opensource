import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/speedtest/speedtest_service.dart';
import '../../../services/storage/prefs.dart';
import '../../dashboard/domain/ip_info_provider.dart';
import '../../history/domain/speed_test_history_notifier.dart';
import '../../history/domain/speed_test_record.dart';
import '../../servers/data/server_preferences_repository.dart';
import '../../servers/domain/server_providers.dart';
import 'speedtest_state.dart';

double rollingAverage(List<double> values, {int window = 5}) {
  if (values.isEmpty) {
    return 0;
  }
  final filtered = values.where((v) => v > 0.05).toList();
  if (filtered.isEmpty) {
    return 0;
  }
  final start = filtered.length > window ? filtered.length - window : 0;
  final slice = filtered.sublist(start);
  final sum = slice.fold<double>(0, (acc, value) => acc + value);
  return sum / slice.length;
}

double _smoothMbps(double previous, double sample, {double alpha = 0.35}) {
  if (sample <= 0.05) {
    return previous;
  }
  if (previous <= 0.05) {
    return sample;
  }
  return previous * (1 - alpha) + sample * alpha;
}

class SpeedTestController extends StateNotifier<SpeedTestState> {
  SpeedTestController(this._ref, this._service)
      : super(SpeedTestState.initial());

  final Ref _ref;
  final SpeedTestService _service;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  Future<void> run({required bool isVpnTest}) async {
    if (state.status == SpeedTestStatus.running || state.status == SpeedTestStatus.preparing) {
      return;
    }
    state = state.copyWith(
      status: SpeedTestStatus.preparing,
      phase: SpeedTestPhase.locating,
      isVpnTest: isVpnTest,
      errorMessage: null,
      downloadMbps: 0,
      uploadMbps: 0,
      liveMbps: 0,
      downloadSeries: const <double>[],
      uploadSeries: const <double>[],
      serverName: null,
    );

    try {
      final prefs = await _ref.read(prefsStoreProvider.future);
      final downloadSeries = <double>[];
      final uploadSeries = <double>[];
      var hadError = false;
      DateTime? completionTimestamp;

      state = state.copyWith(status: SpeedTestStatus.running);

      _connectivitySubscription?.cancel();
      _connectivitySubscription = null;
      if (!isVpnTest) {
        _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
          final hasNetwork = results.isNotEmpty &&
              !results.every((r) => r == ConnectivityResult.none);
          if (!hasNetwork && state.status == SpeedTestStatus.running) {
            hadError = true;
            unawaited(_service.cancelTest());
            state = state.copyWith(
              status: SpeedTestStatus.error,
              phase: SpeedTestPhase.idle,
              errorMessage: 'Network disconnected during test.',
              downloadSeries: const <double>[],
              uploadSeries: const <double>[],
              liveMbps: 0,
            );
            _connectivitySubscription?.cancel();
            _connectivitySubscription = null;
          }
        });
      }

      try {
        await _service.runTest(
          onPhase: (phase) {
            state = state.copyWith(phase: phase, errorMessage: null);
          },
          onServerSelected: (name) {
            state = state.copyWith(serverName: name);
          },
          onPingSample: (pingMs) {
            state = state.copyWith(ping: Duration(milliseconds: pingMs));
          },
          onDownloadProgress: (mbps, _) {
            if (mbps.isNaN || mbps.isInfinite) return;
            if (mbps > 0.05) {
              downloadSeries.add(mbps);
            }
            final smoothed = _smoothMbps(state.downloadMbps, mbps);
            state = state.copyWith(
              phase: SpeedTestPhase.download,
              downloadSeries: List<double>.from(downloadSeries),
              downloadMbps: smoothed > 0 ? smoothed : rollingAverage(downloadSeries),
              liveMbps: _smoothMbps(state.liveMbps, mbps),
              errorMessage: null,
            );
          },
          onUploadProgress: (mbps, _) {
            if (mbps.isNaN || mbps.isInfinite) return;
            if (mbps > 0.05) {
              uploadSeries.add(mbps);
            }
            final smoothed = _smoothMbps(state.uploadMbps, mbps);
            state = state.copyWith(
              phase: SpeedTestPhase.upload,
              uploadSeries: List<double>.from(uploadSeries),
              uploadMbps: smoothed > 0 ? smoothed : rollingAverage(uploadSeries),
              liveMbps: _smoothMbps(state.liveMbps, mbps),
              errorMessage: null,
            );
          },
          onError: (message) {
            _connectivitySubscription?.cancel();
            _connectivitySubscription = null;
            hadError = true;
            state = state.copyWith(
              status: SpeedTestStatus.error,
              phase: SpeedTestPhase.idle,
              errorMessage: _friendlyPluginError(message),
              downloadSeries: const <double>[],
              uploadSeries: const <double>[],
              liveMbps: 0,
            );
          },
          onCompleted: ({required downloadMbps, required uploadMbps, required pingMs}) {
            _connectivitySubscription?.cancel();
            _connectivitySubscription = null;
            completionTimestamp = DateTime.now().toUtc();
            if (downloadSeries.isEmpty && downloadMbps > 0) {
              downloadSeries.add(downloadMbps);
            }
            if (uploadSeries.isEmpty && uploadMbps > 0) {
              uploadSeries.add(uploadMbps);
            }
            state = state.copyWith(
              status: SpeedTestStatus.complete,
              phase: SpeedTestPhase.idle,
              downloadMbps: downloadMbps > 0 ? downloadMbps : rollingAverage(downloadSeries),
              uploadMbps: uploadMbps > 0 ? uploadMbps : rollingAverage(uploadSeries),
              ping: pingMs > 0 ? Duration(milliseconds: pingMs) : state.ping,
              downloadSeries: List<double>.from(downloadSeries),
              uploadSeries: List<double>.from(uploadSeries),
              lastRun: completionTimestamp,
              liveMbps: 0,
              errorMessage: null,
            );
          },
        );
      } on Object catch (error) {
        _connectivitySubscription?.cancel();
        _connectivitySubscription = null;
        hadError = true;
        state = state.copyWith(
          status: SpeedTestStatus.error,
          phase: SpeedTestPhase.idle,
          errorMessage: _friendlyException(error),
          downloadSeries: const <double>[],
          uploadSeries: const <double>[],
          liveMbps: 0,
        );
      }

      if (hadError || state.status != SpeedTestStatus.complete) {
        return;
      }

      String ip = state.ip ?? '';
      try {
        final ipInfo = await fetchIpInfo();
        if (ipInfo.ip != null && ipInfo.ip!.isNotEmpty) {
          ip = ipInfo.ip!.trim();
        }
      } catch (_) {}      final updated = state.copyWith(
        ip: ip.isNotEmpty ? ip : state.ip,
        lastRun: completionTimestamp ?? state.lastRun ?? DateTime.now().toUtc(),
      );
      state = updated;
      await prefs.setString('speedtest_last', jsonEncode(_serializeResult(updated)));
      final history = _ref.read(speedTestHistoryProvider.notifier);
      unawaited(history.addRecord(
        SpeedTestRecord(
          timestamp: updated.lastRun ?? DateTime.now().toUtc(),
          downloadMbps: updated.downloadMbps,
          uploadMbps: updated.uploadMbps,
          pingMs: updated.ping?.inMilliseconds,
          ip: updated.ip,
        ),
      ));
      final server = _ref.read(selectedServerProvider);
      if (isVpnTest &&
          server != null &&
          updated.downloadMbps > 0 &&
          updated.uploadMbps > 0) {
        final prefsRepo = _ref.read(serverPreferencesRepositoryProvider);
        if (prefsRepo != null) {
          unawaited(prefsRepo.saveServerSpeedCache(
            server.id,
            ServerSpeedCache(
              downloadMbps: updated.downloadMbps,
              uploadMbps: updated.uploadMbps,
              pingMs: updated.ping?.inMilliseconds,
            ),
          ).then((_) {
            _ref.invalidate(serverSpeedCacheProvider);
          }));
        }
      }
    } catch (error) {
      _connectivitySubscription?.cancel();
      _connectivitySubscription = null;
      state = state.copyWith(
        status: SpeedTestStatus.error,
        phase: SpeedTestPhase.idle,
        errorMessage: _friendlyException(error),
        downloadSeries: const <double>[],
        uploadSeries: const <double>[],
        liveMbps: 0,
      );
    }
  }

  Future<void> hydrate() async {
    final prefs = await _ref.read(prefsStoreProvider.future);
    final raw = prefs.getString('speedtest_last');
    if (raw == null) return;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      state = SpeedTestState(
        status: SpeedTestStatus.complete,
        ping: data['pingMs'] != null ? Duration(milliseconds: data['pingMs'] as int) : null,
        downloadMbps: (data['download'] as num?)?.toDouble() ?? 0,
        uploadMbps: (data['upload'] as num?)?.toDouble() ?? 0,
        ip: data['ip'] as String?,
        downloadSeries: ((data['downloadSeries'] as List<dynamic>?) ?? [])
            .map((e) => (e as num).toDouble())
            .toList(),
        uploadSeries: ((data['uploadSeries'] as List<dynamic>?) ?? [])
            .map((e) => (e as num).toDouble())
            .toList(),
        lastRun: data['lastRun'] != null ? DateTime.parse(data['lastRun'] as String) : null,
        isVpnTest: data['isVpnTest'] as bool? ?? false,
      );
    } catch (_) {
      // ignore corrupt data
    }
  }

  Map<String, dynamic> _serializeResult(SpeedTestState state) {
    return {
      'pingMs': state.ping?.inMilliseconds,
      'download': state.downloadMbps,
      'upload': state.uploadMbps,
      'ip': state.ip,
      'downloadSeries': state.downloadSeries,
      'uploadSeries': state.uploadSeries,
      'lastRun': state.lastRun?.toIso8601String(),
      'isVpnTest': state.isVpnTest,
    };
  }
}

String _friendlyPluginError(String message) {
  final normalized = message.trim().toLowerCase();
  if (normalized.contains('connection') ||
      normalized.contains('socket') ||
      normalized.contains('host lookup') ||
      normalized.contains('refused') ||
      normalized.contains('no speed test server')) {
    return 'Unable to reach the speed test servers. Check your network or try again later.';
  }
  if (normalized.contains('timeout')) {
    return 'The speed test timed out before it could finish. Try again in a moment.';
  }
  if (normalized.contains('cancel')) {
    return 'Speed test was cancelled. Tap start to try again.';
  }
  return message.isEmpty ? 'The speed test encountered an unexpected error.' : message;
}

String _friendlyException(Object error) {
  if (error is TimeoutException) {
    return 'The speed test took too long and timed out. Please try again.';
  }
  if (error is SocketException) {
    return 'Unable to reach the speed test servers. Please check your connection and try again.';
  }
  if (error is PlatformException) {
    return error.message ?? 'The speed test could not start. Please try again.';
  }
  return error.toString();
}

final speedTestServiceProvider = Provider<SpeedTestService>((ref) {
  return SpeedTestService();
});

final speedTestControllerProvider =
    StateNotifierProvider<SpeedTestController, SpeedTestState>((ref) {
  final service = ref.watch(speedTestServiceProvider);
  final controller = SpeedTestController(ref, service);
  unawaited(controller.hydrate());
  return controller;
});
