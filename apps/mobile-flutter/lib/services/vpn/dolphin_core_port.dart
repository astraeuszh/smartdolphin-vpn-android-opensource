import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/device/memory_tier.dart';
import '../../features/game_mode/domain/game_decel_tier.dart';
import '../../features/game_mode/domain/game_mode_speed.dart';
import '../../features/settings/domain/advanced_settings_config.dart';
import '../../features/settings/domain/routing_config.dart';
import '../../features/settings/domain/traffic_mode.dart';
import '../../features/settings/domain/split_tunnel_config.dart';
import 'models/vpn.dart';
import 'models/vpn_status.dart' as model;
import 'node_table.dart';
import 'vpn_port.dart';
import 'vpn_stage.dart';

/// Dolphin-Core (sing-box / libbox) VPN port. Replaces the OpenVPN port.
/// Drives the native `BoxService` (VpnService) over method/event channels and
/// generates the sing-box config from the canonical node table.
class DolphinCorePort implements VpnPort {
  DolphinCorePort();

  static const MethodChannel _control = MethodChannel('smartdolphin/core');
  static const EventChannel _stageEvents = EventChannel('smartdolphin/core/stage');
  static const EventChannel _statusEvents = EventChannel('smartdolphin/core/status');

  final StreamController<String> _intentActionsController = StreamController<String>.broadcast();
  final StreamController<VPNStage> _stageController = StreamController<VPNStage>.broadcast();
  final StreamController<model.VpnStatus> _statusController = StreamController<model.VpnStatus>.broadcast();

  StreamSubscription<dynamic>? _stageSub;
  StreamSubscription<dynamic>? _statusSub;

  bool _isConnected = false;
  bool _isInitialized = false;
  model.VpnStatus? _lastStatus;

  // Settings captured from the app (drop-in for the old OpenVpnPort setters).
  SdProtocol _protocol = SdProtocol.reality;
  bool _globalMode = false;
  bool _bypassLan = true;
  bool _autoRouteSystem = true;
  bool _forceDnsThroughTunnel = true;
  bool _blockLocalDns = true;
  List<String> _includePackages = const [];
  List<String> _excludePackages = const [];
  String _dns = '8.8.8.8';
  bool _disableIpv6 = true;
  int _mtu = 1420;

  @override
  bool get isSupported => !kIsWeb;

  @override
  Stream<String> get intentActions => _intentActionsController.stream;

  @override
  Stream<VPNStage> get stageStream => _stageController.stream;

  @override
  Stream<model.VpnStatus> get statusStream => _statusController.stream;

  @override
  Future<bool> isConnected() async => _isConnected;

  Future<void> initialize() async {
    if (_isInitialized || kIsWeb) return;
    _stageSub = _stageEvents.receiveBroadcastStream().listen((event) {
      final stage = vpnStageFromString(event?.toString());
      _isConnected = stage == VPNStage.connected;
      _stageController.add(stage);
    }, onError: (_) {});
    _statusSub = _statusEvents.receiveBroadcastStream().listen((event) {
      final s = _parseStatus(event);
      if (s != null) {
        _lastStatus = s;
        _statusController.add(s);
      }
    }, onError: (_) {});
    _isInitialized = true;
  }

  @override
  Future<bool> prepare() async {
    if (kIsWeb) return false;
    if (!_isInitialized) await initialize();
    try {
      final granted = await _control.invokeMethod<bool>('prepare');
      return granted ?? false;
    } on PlatformException catch (e) {
      debugPrint('[DolphinCorePort] prepare failed: $e');
      return false;
    }
  }

  @override
  Future<bool> connect(Vpn server) async {
    if (kIsWeb) return false;
    if (!_isInitialized) await initialize();
    try {
      final node = nodeForHostOrCountry(server.ip, server.countryLong);
      final config = buildSingBoxConfig(
        node: node,
        protocol: _protocol,
        globalMode: _globalMode,
        dnsServer: _dns,
        mtu: _mtu,
        disableIpv6: _disableIpv6,
        bypassLan: _bypassLan,
        autoRouteSystem: _autoRouteSystem,
        forceDnsThroughTunnel: _forceDnsThroughTunnel,
        blockLocalDns: _blockLocalDns,
        includePackages: _includePackages,
        excludePackages: _excludePackages,
      );
      _stageController.add(VPNStage.connecting);
      // Always stop any lingering native box before starting fresh (prevents zombie
      // tun after long background / reconnect without full teardown).
      try {
        await _control.invokeMethod<void>('stop');
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 800));
      final ok = await _control.invokeMethod<bool>('start', {
        'config': config,
        'node': node.tag,
        'profile': '${node.tag} · ${server.countryLong}',
      });
      if (ok != true) {
        _stageController.add(VPNStage.error);
        return false;
      }
      return true;
    } catch (e, st) {
      debugPrint('[DolphinCorePort] connect error: $e\n$st');
      _isConnected = false;
      _stageController.add(VPNStage.error);
      return false;
    }
  }

  @override
  Future<void> disconnect() async {
    try {
      await _control.invokeMethod<void>('stop');
    } catch (e) {
      debugPrint('[DolphinCorePort] disconnect error: $e');
    }
    _isConnected = false;
    try {
      _stageController.add(VPNStage.disconnected);
    } catch (_) {}
  }

  @override
  Future<Map<String, dynamic>> getTunnelStats() async {
    return _lastStatus?.toJson() ?? <String, dynamic>{};
  }

  @override
  Future<void> extendSession(Duration duration, {String? publicIp}) async {
    // Session extension is handled at the app level, not the VPN level.
  }

  void dispose() {
    _stageSub?.cancel();
    _statusSub?.cancel();
    _intentActionsController.close();
    _stageController.close();
    _statusController.close();
  }

  // --- drop-in setters (kept compatible with the old OpenVpnPort callers) ---

  /// Reality / Hysteria2 / WireGuard. Defaults to Reality (most reliable).
  void setProtocol(SdProtocol protocol) => _protocol = protocol;

  void setRoutingConfig(RoutingConfig config) {
    // global → all traffic through proxy; auto → built-in CN/Baidu direct split.
    _globalMode = config.mode == TrafficMode.global;
    _bypassLan = config.bypassLan;
    _autoRouteSystem = config.autoRouteSystem;
  }

  void setAdvancedConfig(AdvancedSettingsConfig config) {
    _disableIpv6 = config.disableIpv6WhenConnected || config.blockIpv6Dns;
    _forceDnsThroughTunnel = config.forceDnsThroughTunnel;
    _blockLocalDns = config.blockLocalDns;
  }

  /// Per-app split tunnelling. includeApps → only these apps use the VPN;
  /// excludeApps → these apps bypass it; allTraffic → everything tunnels.
  void setSplitTunnel(SplitTunnelMode mode, List<String> packages) {
    final pkgs = packages.where((p) => p.trim().isNotEmpty).toList();
    switch (mode) {
      case SplitTunnelMode.includeApps:
        _includePackages = pkgs;
        _excludePackages = const [];
        break;
      case SplitTunnelMode.excludeApps:
        _excludePackages = pkgs;
        _includePackages = const [];
        break;
      case SplitTunnelMode.allTraffic:
        _includePackages = const [];
        _excludePackages = const [];
        break;
    }
  }

  void setDnsServers(List<String> servers) {
    final first = servers.map((s) => s.trim()).firstWhere((s) => s.isNotEmpty, orElse: () => '');
    if (first.isNotEmpty) _dns = first;
  }

  // The following map to OpenVPN-tunnel shaping that sing-box handles
  // differently; kept as no-ops so existing callers keep working. They can be
  // wired into the config later (settings pass).
  void setBypassPackages(List<String> packages) {}
  void setGameTrafficMode(GameModeSpeed mode) {}
  void setGameDecelTier(GameDecelTier tier) {}
  void setGameModeOverlayActive(bool active) {}
  void setMemoryTier(MemoryTier tier) {
    _mtu = tier == MemoryTier.low ? 1280 : 1420;
  }

  void setSmartStableTuning(bool enabled) {
    if (enabled) _mtu = 1200;
  }

  void setAccountTrafficThrottle(bool enabled) {}

  model.VpnStatus? _parseStatus(dynamic event) {
    try {
      Map<String, dynamic> m;
      if (event is String) {
        m = jsonDecode(event) as Map<String, dynamic>;
      } else if (event is Map) {
        m = Map<String, dynamic>.from(event);
      } else {
        return null;
      }
      return model.VpnStatus(
        duration: (m['duration'] ?? '00:00:00').toString(),
        connectedOn: null,
        // byteIn/byteOut are CUMULATIVE counters (libbox *Total) used by the
        // session ticker / usage accounting.
        byteIn: (m['downTotal'] ?? m['byteIn'] ?? '0').toString(),
        byteOut: (m['upTotal'] ?? m['byteOut'] ?? '0').toString(),
        packetsIn: (m['packetsIn'] ?? '0').toString(),
        packetsOut: (m['packetsOut'] ?? '0').toString(),
        // Instantaneous bytes/sec (libbox downlink/uplink) — the live speed
        // meter & sparkline use these directly instead of guessing from deltas.
        byteInRate: (m['down'] ?? '0').toString(),
        byteOutRate: (m['up'] ?? '0').toString(),
      );
    } catch (_) {
      return null;
    }
  }
}
