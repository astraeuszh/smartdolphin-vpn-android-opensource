import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/vpn/vpn_provider.dart';
import '../../session/domain/session_controller.dart';
import '../../session/domain/session_status.dart';

/// Live throughput (Mbps) when connected.
class TunnelThroughputState {
  const TunnelThroughputState({
    this.downloadMbps,
    this.uploadMbps,
  });

  final double? downloadMbps;
  final double? uploadMbps;
}

class TunnelThroughputNotifier extends StateNotifier<TunnelThroughputState>
    with WidgetsBindingObserver {
  TunnelThroughputNotifier(this._ref) : super(const TunnelThroughputState()) {
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
  int _lastRxBytes = 0;
  int _lastTxBytes = 0;
  DateTime? _lastSampleTime;
  bool _foreground = true;

  static const _emaAlpha = 0.72;
  static const _minMbps = 0.05;
  static const _maxReasonableMbps = 1000.0;

  void _onSessionChanged(dynamic prev, dynamic next) {
    if (next.status == SessionStatus.connected) {
      _startPolling();
    } else {
      _stopPolling();
      state = const TunnelThroughputState();
    }
  }

  void _startPolling() {
    _stopPolling();
    _lastRxBytes = 0;
    _lastTxBytes = 0;
    _lastSampleTime = null;
    if (_foreground) {
      _timer = Timer.periodic(const Duration(seconds: 10), (_) => _poll());
      _poll();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _stopPolling();
      return;
    }
    if (_ref.read(sessionControllerProvider).status ==
        SessionStatus.connected) {
      _startPolling();
    }
  }

  void _stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  double? _smooth(double? previous, double sample) {
    if (sample < _minMbps || sample > _maxReasonableMbps) {
      return previous;
    }
    if (previous == null || previous < _minMbps) {
      return sample;
    }
    return previous * (1 - _emaAlpha) + sample * _emaAlpha;
  }

  /// EMA that also tracks downward (toward 0), for the live instantaneous rate.
  double _ema(double? previous, double sample) {
    if (sample > _maxReasonableMbps) return previous ?? 0;
    if (previous == null) return sample;
    return previous * (1 - _emaAlpha) + sample * _emaAlpha;
  }

  Future<void> _poll() async {
    try {
      final port = _ref.read(openVpnPortProvider);
      final stats = await port.getTunnelStats();

      // libbox uplink/downlink are bytes/sec deltas when TrafficAvailable=true.
      // VpnStatus.toJson() always includes byte_*_rate keys (default "0"), so
      // we must NOT treat key presence as "live rate available" -only use the
      // rate path when the core is actually reporting non-zero throughput.
      final inRate = _parseBytes(stats['byte_in_rate']);
      final outRate = _parseBytes(stats['byte_out_rate']);
      if (inRate > 0 || outRate > 0) {
        final dl = (inRate * 8) / 1000000;
        final ul = (outRate * 8) / 1000000;
        state = TunnelThroughputState(
          downloadMbps: _ema(state.downloadMbps, dl),
          uploadMbps: _ema(state.uploadMbps, ul),
        );
        return;
      }

      final rx = _parseBytes(stats['byte_in'] ?? stats['rxBytes']);
      final tx = _parseBytes(stats['byte_out'] ?? stats['txBytes']);
      final now = DateTime.now();

      if (_lastSampleTime != null && rx >= _lastRxBytes && tx >= _lastTxBytes) {
        final elapsed =
            now.difference(_lastSampleTime!).inMilliseconds / 1000.0;
        if (elapsed > 0.5) {
          final rxDelta = (rx - _lastRxBytes) / elapsed;
          final txDelta = (tx - _lastTxBytes) / elapsed;
          final instantDl = (rxDelta * 8) / 1000000;
          final instantUl = (txDelta * 8) / 1000000;
          state = TunnelThroughputState(
            downloadMbps: _smooth(state.downloadMbps, instantDl),
            uploadMbps: _smooth(state.uploadMbps, instantUl),
          );
        }
      } else if (_lastSampleTime == null) {
        // First sample after connect -seed counters so the next tick can delta.
        state = TunnelThroughputState(
          downloadMbps: state.downloadMbps ?? 0,
          uploadMbps: state.uploadMbps ?? 0,
        );
      } else {
        // Idle: decay live-rate EMA toward zero instead of freezing.
        state = TunnelThroughputState(
          downloadMbps: _ema(state.downloadMbps, 0),
          uploadMbps: _ema(state.uploadMbps, 0),
        );
      }
      _lastRxBytes = rx;
      _lastTxBytes = tx;
      _lastSampleTime = now;
    } catch (_) {
      // ignore
    }
  }

  static int _parseBytes(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toInt();
    final s = value.toString().trim().replaceAll(RegExp(r'[,\s]'), '');
    return int.tryParse(s) ?? 0;
  }

  @override
  void dispose() {
    _stopPolling();
    WidgetsBinding.instance.removeObserver(this);
    _sub?.close();
    super.dispose();
  }
}

final tunnelThroughputProvider =
    StateNotifierProvider<TunnelThroughputNotifier, TunnelThroughputState>(
        (ref) => TunnelThroughputNotifier(ref));
