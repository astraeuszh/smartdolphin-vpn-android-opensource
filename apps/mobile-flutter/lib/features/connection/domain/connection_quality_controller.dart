import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app.dart';
import '../../home/domain/home_local_stats_provider.dart';
import '../../home/domain/home_packet_loss_provider.dart';
import '../../servers/domain/server.dart';
import '../../servers/domain/server_providers.dart';
import '../../session/domain/session_controller.dart';
import '../../session/domain/session_state.dart';
import '../../session/domain/session_status.dart';
import '../../settings/domain/preferences_controller.dart';
import 'connection_quality.dart';
import 'connection_quality_state.dart';

class ConnectionQualityController
    extends StateNotifier<ConnectionQualityState> {
  ConnectionQualityController(this._ref)
      : super(ConnectionQualityState.initial()) {
    _sessionSub = _ref.listen(sessionControllerProvider, _handleSession,
        fireImmediately: true);
    _latencySub = _ref.listen(homeSystemLatencyProvider, (_, __) => _evaluate(),
        fireImmediately: true);
    _lossSub = _ref.listen(homePacketLossProvider, (_, __) => _evaluate(),
        fireImmediately: true);
  }

  final Ref _ref;
  late final ProviderSubscription<SessionState> _sessionSub;
  late final ProviderSubscription<AsyncValue<int?>> _latencySub;
  late final ProviderSubscription<AsyncValue<double?>> _lossSub;

  void _handleSession(SessionState? previous, SessionState next) {
    _evaluate();
  }

  void refresh() => _evaluate();

  void _evaluate() {
    final session = _ref.read(sessionControllerProvider);
    final latencyMs = _ref.read(homeSystemLatencyProvider).valueOrNull;
    final packetLoss = _ref.read(homePacketLossProvider).valueOrNull;

    ConnectionQuality quality;
    if (session.status != SessionStatus.connected) {
      quality = ConnectionQuality.offline;
    } else {
      final pingMs = latencyMs ?? 999;
      final loss = packetLoss ?? 0;
      if (pingMs <= 80 && loss < 2) {
        quality = ConnectionQuality.excellent;
      } else if (pingMs <= 150 && loss < 5) {
        quality = ConnectionQuality.good;
      } else if (pingMs <= 300 && loss < 15) {
        quality = ConnectionQuality.fair;
      } else {
        quality = ConnectionQuality.poor;
      }
    }

    state = state.copyWith(
      quality: quality,
      ping: latencyMs != null ? Duration(milliseconds: latencyMs) : null,
    );

    if (quality == ConnectionQuality.poor) {
      unawaited(_maybeAutoSwitch());
    }
  }

  Future<void> _maybeAutoSwitch() async {
    if (state.isSwitching) return;
    final enabled = _ref
        .read(preferencesControllerProvider.select((v) => v.autoServerSwitch));
    if (!enabled) return;

    final session = _ref.read(sessionControllerProvider);
    if (session.status != SessionStatus.connected) return;

    final lastSwitch = state.lastSwitch;
    if (lastSwitch != null &&
        DateTime.now().difference(lastSwitch) < const Duration(minutes: 5)) {
      return;
    }

    final servers = _ref.read(serversProvider);
    if (servers.isEmpty) return;
    final current = _ref.read(selectedServerProvider);
    final target = _chooseUsPreferredServer(servers, current);
    if (target == null || (current != null && current.id == target.id)) return;

    final ctx = _ref.read(navigatorKeyProvider).currentContext;
    if (ctx == null || !ctx.mounted) return;

    state = state.copyWith(isSwitching: true);
    try {
      await _ref
          .read(sessionControllerProvider.notifier)
          .switchToServerAndConnect(
            context: ctx,
            server: target,
          );
      state = state.copyWith(lastSwitch: DateTime.now());
    } finally {
      state = state.copyWith(isSwitching: false);
    }
  }

  Server? _chooseUsPreferredServer(List<Server> servers, Server? current) {
    final usServers =
        servers.where((s) => s.countryCode.toUpperCase() == 'US').toList();
    if (usServers.isNotEmpty) {
      if (current != null &&
          usServers.any((s) => s.id == current.id) &&
          usServers.length > 1) {
        final idx = usServers.indexWhere((s) => s.id == current.id);
        return usServers[(idx + 1) % usServers.length];
      }
      return usServers.first;
    }
    if (servers.length <= 1) return servers.isNotEmpty ? servers.first : null;
    if (current == null) return servers.first;
    final index = servers.indexWhere((s) => s.id == current.id);
    if (index == -1) return servers.first;
    return servers[(index + 1) % servers.length];
  }

  @override
  void dispose() {
    _sessionSub.close();
    _latencySub.close();
    _lossSub.close();
    super.dispose();
  }
}

final connectionQualityControllerProvider =
    StateNotifierProvider<ConnectionQualityController, ConnectionQualityState>(
        (ref) {
  return ConnectionQualityController(ref);
});
