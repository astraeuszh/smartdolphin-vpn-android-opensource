import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../connection/domain/tunnel_throughput_provider.dart';
import '../../session/domain/session_controller.dart';
import '../../session/domain/session_status.dart';

/// 流量历史采样，用于仪表盘 sparkline 波浪线
class TrafficHistoryState {
  const TrafficHistoryState({
    this.uploadSamples = const [],
    this.downloadSamples = const [],
  });

  final List<double> uploadSamples;
  final List<double> downloadSamples;

  static const int maxSamples = 45;
}

class TrafficHistoryNotifier extends StateNotifier<TrafficHistoryState>
    with WidgetsBindingObserver {
  TrafficHistoryNotifier(this._ref) : super(const TrafficHistoryState()) {
    WidgetsBinding.instance.addObserver(this);
    _foreground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _sub = _ref.listen(
      sessionControllerProvider,
      _onSessionChanged,
      fireImmediately: true,
    );
  }

  final Ref _ref;
  ProviderSubscription<dynamic>? _sub;
  Timer? _timer;
  bool _foreground = true;

  void _onSessionChanged(dynamic prev, dynamic next) {
    if (next.status == SessionStatus.connected && _foreground) {
      _startSampling();
    } else {
      _stopSampling();
      state = const TrafficHistoryState();
    }
  }

  void _startSampling() {
    _stopSampling();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _sample());
    _sample();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _stopSampling();
    } else if (_ref.read(sessionControllerProvider).status ==
        SessionStatus.connected) {
      _startSampling();
    }
  }

  void _stopSampling() {
    _timer?.cancel();
    _timer = null;
  }

  void _sample() {
    final throughput = _ref.read(tunnelThroughputProvider);
    final upload = throughput.uploadMbps ?? 0.0;
    final download = throughput.downloadMbps ?? 0.0;

    var uploadList = [...state.uploadSamples, upload];
    var downloadList = [...state.downloadSamples, download];
    if (uploadList.length > TrafficHistoryState.maxSamples) {
      uploadList = uploadList
          .sublist(uploadList.length - TrafficHistoryState.maxSamples);
    }
    if (downloadList.length > TrafficHistoryState.maxSamples) {
      downloadList = downloadList
          .sublist(downloadList.length - TrafficHistoryState.maxSamples);
    }
    state = TrafficHistoryState(
        uploadSamples: uploadList, downloadSamples: downloadList);
  }

  @override
  void dispose() {
    _stopSampling();
    WidgetsBinding.instance.removeObserver(this);
    _sub?.close();
    super.dispose();
  }
}

final trafficHistoryProvider =
    StateNotifierProvider<TrafficHistoryNotifier, TrafficHistoryState>(
        (ref) => TrafficHistoryNotifier(ref));
