import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:meta/meta.dart';
import 'package:openvpn_flutter/openvpn_flutter.dart';

import '../../core/device/memory_tier.dart';
import '../../core/platform/runtime_platform.dart';
import '../../core/errors/app_error.dart';
import 'dns_resolve.dart';
import '../../features/game_mode/domain/game_decel_tier.dart';
import '../../features/game_mode/domain/game_mode_speed.dart';
import '../../features/settings/domain/routing_config.dart';
import '../../features/settings/domain/traffic_mode.dart';
import 'models/vpn.dart';
import 'models/vpn_config.dart';
import 'models/vpn_status.dart' as model;
import 'vpn_port.dart';

/// OpenVPN port（openvpn_flutter）。
/// 多台手机同一路由器/同 WiFi 时卡顿常见于：共享上行带宽与空口竞争，与服务器并发数无必然关系。
class OpenVpnPort implements VpnPort {
  OpenVpnPort();

  OpenVPN? _engine;
  MemoryTier _memoryTier = MemoryTier.mid;
  final StreamController<String> _intentActionsController =
      StreamController<String>.broadcast();
  final StreamController<VPNStage> _stageController =
      StreamController<VPNStage>.broadcast();
  final StreamController<model.VpnStatus> _statusController =
      StreamController<model.VpnStatus>.broadcast();

  bool _isConnected = false;
  bool _isInitialized = false;
  Vpn? _currentServer;
  RoutingConfig _routingConfig = const RoutingConfig();
  List<String> _dnsServers = const [];
  bool _smartStableTuning = false;
  GameModeSpeed _gameTrafficMode = GameModeSpeed.accel;
  GameDecelTier _gameDecelTier = GameDecelTier.medium;
  /// 仅全屏游戏模式打开时为 true；与日常 VPN 分流，避免持久化「减速」误伤普通连接。
  bool _gameModeOverlayActive = false;

  /// 游戏模式「减速」：在 **单条** OpenVPN 隧道内注入极低带宽与小 MTU（无法在同一连接上叠多层独立加密，多跳需服务端链）。
  void setGameTrafficMode(GameModeSpeed mode) {
    _gameTrafficMode = mode;
  }

  void setGameModeOverlayActive(bool active) {
    _gameModeOverlayActive = active;
  }

  /// 与设置里「低/中/高/超级」对应，仅 [GameModeSpeed.decel] 时注入 shaper。
  void setGameDecelTier(GameDecelTier tier) {
    _gameDecelTier = tier;
  }

  /// When true, injects smaller MTU / mssfix for weak networks (SmartStable).
  void setSmartStableTuning(bool enabled) {
    _smartStableTuning = enabled;
  }

  /// 低端机：略收紧 MTU、零缓冲，减轻内核与用户态开销（APK 体积≠运行时 CPU）。
  void setMemoryTier(MemoryTier tier) {
    _memoryTier = tier;
  }

  @override
  bool get isSupported => !kIsWeb;

  @override
  Stream<String> get intentActions => _intentActionsController.stream;

  @override
  Future<bool> isConnected() async => _isConnected;

  @override
  Stream<VPNStage> get stageStream => _stageController.stream;

  @override
  Stream<model.VpnStatus> get statusStream => _statusController.stream;

  static const _vpnChannel = MethodChannel('com.example.vpn/VpnChannel');

  void setRoutingConfig(RoutingConfig config) {
    _routingConfig = config;
  }

  void setDnsServers(List<String> servers) {
    _dnsServers = List.unmodifiable(servers.where((s) => s.trim().isNotEmpty));
  }

  @override
  Future<bool> prepare() async {
    if (kIsWeb) {
      return false;
    }
    if (isAndroidNative) {
      // 先调用原生 VpnService.prepare()，确保系统弹出「是否允许建立 VPN 连接」对话框
      // openvpn_flutter 的 requestPermissionAndroid 在某些设备上可能不触发弹窗
      try {
        final nativeGranted = await _vpnChannel.invokeMethod<bool>('prepare');
        if (nativeGranted != true) {
          debugPrint('[OpenVpnPort] Native VPN permission denied by user');
          return false;
        }
        debugPrint('[OpenVpnPort] Native VPN permission granted');
      } on PlatformException catch (e) {
        debugPrint('[OpenVpnPort] Native prepare failed: $e');
        return false;
      }
    }

    if (!_isInitialized) {
      await initialize();
    }
    if (_engine == null) {
      return false;
    }
    if (isAndroidNative) {
      final granted = await _engine!.requestPermissionAndroid();
      return granted;
    }
    return true;
  }

  /// Initialize the OpenVPN engine
  Future<void> initialize() async {
    if (_isInitialized) return;
    if (kIsWeb) {
      return;
    }

    try {
      _engine = OpenVPN(
        onVpnStatusChanged: (data) {
          if (data == null) {
            return;
          }
          final converted = _convertStatus(data);
          _lastStatus = converted;
          _statusController.add(converted);
        },
        onVpnStageChanged: (stage, rawStage) {
          _isConnected = stage == VPNStage.connected;
          _stageController.add(stage);
          debugPrint('[OpenVpnPort] Stage changed: $stage (raw: $rawStage)');
        },
      );

      await _engine!.initialize(
        groupIdentifier: null,
        providerBundleIdentifier: null,
        localizedDescription: 'SmartDolphinVPN',
      );

      _isInitialized = true;
    } catch (e) {
      print('Error initializing OpenVPN: $e');
      _isInitialized = false;
      rethrow;
    }
  }

  @override
  Future<bool> connect(Vpn server) async {
    if (kIsWeb) {
      debugPrint('[OpenVpnPort] connect() skipped on web');
      return false;
    }
    try {
      debugPrint('[OpenVpnPort] connect() invoked for ${server.countryLong}');
      if (!_isInitialized) {
        await initialize();
      }

      if (_isConnected) {
        await disconnect();
        await Future.delayed(const Duration(seconds: 1));
      }

      _currentServer = server;

      late final String configText;
      try {
        configText = server.openVpnConfig;
        debugPrint('[OpenVpnPort] Successfully decoded OpenVPN config, length: ${configText.length}');
      } on AppError catch (error) {
        debugPrint('[OpenVpnPort] Invalid OpenVPN config: $error');
        _stageController.add(VPNStage.error);
        return false;
      }

      if (configText.isEmpty) {
        debugPrint(
            '[OpenVpnPort] Error: Empty OpenVPN config for ${server.countryLong}');
        _stageController.add(VPNStage.error);
        return false;
      }

      final sanitizedConfig =
          await _sanitizeOpenVpnConfig(configText, _routingConfig, smartStable: _smartStableTuning);
      final username = sanitizedConfig.username ?? 'vpn';
      final password = sanitizedConfig.password ?? 'vpn';

      // 证书认证配置：传 null 给 username/password，避免插件误判为需要用户输入
      final isCertAuth = RegExp(r'<cert>', caseSensitive: false).hasMatch(sanitizedConfig.config) &&
          RegExp(r'<key>', caseSensitive: false).hasMatch(sanitizedConfig.config);
      final vpnUsername = isCertAuth ? null : (username.isNotEmpty ? username : 'vpn');
      final vpnPassword = isCertAuth ? null : (password.isNotEmpty ? password : 'vpn');

      debugPrint('[OpenVpnPort] Using username: ${vpnUsername == null ? "(cert auth, null)" : vpnUsername}, password: ${vpnPassword == null ? "(cert auth, null)" : "****"}');
      debugPrint('[OpenVpnPort] Sanitized config length: ${sanitizedConfig.config.length}');
      debugPrint('[OpenVpnPort] Cert-based auth: $isCertAuth');
      
      await _engine!.connect(
        sanitizedConfig.config,
        server.countryLong,
        username: vpnUsername,
        password: vpnPassword,
        certIsRequired: isCertAuth,
      );

      debugPrint('[OpenVpnPort] OpenVPN connect command dispatched');
      return true;
    } catch (e, stackTrace) {
      debugPrint('[OpenVpnPort] Error connecting to VPN: $e');
      debugPrint('[OpenVpnPort] Stack trace: $stackTrace');
      _isConnected = false;
      _stageController.add(VPNStage.error);
      return false;
    }
  }

  @override
  Future<void> disconnect() async {
    try {
      debugPrint('[OpenVpnPort] disconnect() requested');
      if (_engine != null) {
        _engine!.disconnect();
      }
      _isConnected = false;
      _currentServer = null;
      try {
        _stageController.add(VPNStage.disconnected);
      } catch (_) {}
    } catch (e) {
      debugPrint('[OpenVpnPort] Error disconnecting from VPN: $e');
      _isConnected = false;
      _currentServer = null;
      // Don't rethrow - prevent app crash on disconnect
    }
  }

  @override
  Future<Map<String, dynamic>> getTunnelStats() async {
    return _lastStatus?.toJson() ?? <String, dynamic>{};
  }

  @override
  Future<void> extendSession(Duration duration, {String? publicIp}) async {
    // Session extension is handled at the app level, not VPN level
    // This is a no-op for OpenVPN
  }

  /// Dispose resources
  void dispose() {
    _intentActionsController.close();
    _stageController.close();
    _statusController.close();
  }

  model.VpnStatus _convertStatus(VpnStatus status) {
    return model.VpnStatus(
      duration: status.duration ?? '00:00:00',
      connectedOn: status.connectedOn,
      byteIn: status.byteIn ?? '0',
      byteOut: status.byteOut ?? '0',
      packetsIn: status.packetsIn ?? '0',
      packetsOut: status.packetsOut ?? '0',
    );
  }

  String _ensureTrailingNewline(String config) {
    if (config.endsWith('\n')) {
      return config;
    }
    return '$config\n';
  }

  Future<SanitizedOpenVpnConfig> _sanitizeOpenVpnConfig(
    String config,
    RoutingConfig routing, {
    bool smartStable = false,
  }) async {
    debugPrint('[OpenVpnPort] Sanitizing OpenVPN config, original length: ${config.length}');
    var working = config.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    String? username;
    String? password;

    final authBlockPattern = RegExp(
      r'<auth-user-pass>(.*?)</auth-user-pass>',
      dotAll: true,
      caseSensitive: false,
    );

    final match = authBlockPattern.firstMatch(working);
    if (match != null) {
      debugPrint('[OpenVpnPort] Found auth-user-pass block in config');
      final blockContent = match.group(1) ?? '';
      final credentials = blockContent
          .split(RegExp(r'\r?\n'))
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();

      if (credentials.isNotEmpty) {
        username = credentials[0];
        debugPrint('[OpenVpnPort] Extracted username from auth block: $username');
      }
      if (credentials.length > 1) {
        password = credentials[1];
        debugPrint('[OpenVpnPort] Extracted password from auth block: ****');
      }

      working = working.replaceRange(match.start, match.end, '');
    }

    working = working.replaceAll(authBlockPattern, '');

    // 证书认证配置（含 <cert> <key>）不需要 auth-user-pass，添加会破坏连接
    final hasCertAuth = RegExp(r'<cert>', caseSensitive: false).hasMatch(working) &&
        RegExp(r'<key>', caseSensitive: false).hasMatch(working);

    final authLinePattern = RegExp(
      r'^\s*auth-user-pass(?:[ \t]+[^\r\n]+)?\s*$',
      multiLine: true,
    );

    var foundDirective = false;
    working = working.replaceAllMapped(authLinePattern, (match) {
      if (foundDirective) {
        return '';
      }
      foundDirective = true;
      debugPrint('[OpenVpnPort] Found auth-user-pass directive in config');
      return 'auth-user-pass';
    });

    if (!foundDirective && !hasCertAuth) {
      debugPrint('[OpenVpnPort] No auth-user-pass directive found, adding one');
      working = working.trimRight();
      if (working.isNotEmpty && !working.endsWith('\n')) {
        working += '\n';
      }
      working += 'auth-user-pass\n';
    } else if (hasCertAuth) {
      debugPrint('[OpenVpnPort] Cert-based config, skipping auth-user-pass');
    }

    // 注入 keepalive 提高稳定性
    if (!RegExp(r'keepalive\s+\d+\s+\d+', caseSensitive: false).hasMatch(working)) {
      working = working.trimRight();
      if (working.isNotEmpty && !working.endsWith('\n')) working += '\n';
      working += 'keepalive 10 60\n';
    }

    // autoRouteSystem=false：不移送全部流量，移除 redirect-gateway
    if (!routing.autoRouteSystem) {
      final redirectPattern = RegExp(
        r'^\s*redirect-gateway\s+.*$',
        multiLine: true,
        caseSensitive: false,
      );
      working = working.replaceAll(redirectPattern, '');
    } else if (!RegExp(r'^\s*block-ipv6', multiLine: true, caseSensitive: false)
        .hasMatch(working)) {
      // 仅 IPv4 隧道时避免站点走 AAAA/IPv6 导致「已连接但打不开网页」
      working = working.trimRight();
      if (working.isNotEmpty && !working.endsWith('\n')) working += '\n';
      working += 'block-ipv6\n';
    }

    // 自定义 DNS：移除原 config 中的 dhcp-option DNS，注入用户选择的 DNS
    final dhcpDnsPattern = RegExp(
      r'^\s*dhcp-option\s+DNS\s+\S+.*$',
      multiLine: true,
      caseSensitive: false,
    );
    working = working.replaceAll(dhcpDnsPattern, '');
    if (_dnsServers.isNotEmpty) {
      working = working.trimRight();
      if (working.isNotEmpty && !working.endsWith('\n')) working += '\n';
      for (final dns in _dnsServers.take(2)) {
        final ip = dns.trim();
        if (_isValidIpV4(ip)) working += 'dhcp-option DNS $ip\n';
      }
    }

    // Bypass LAN: 局域网直连（10.0.0.0/8 与常见 OpenVPN 隧道 10.8.x.x 重叠，需显式把隧道网段拉回 VPN）
    if (routing.bypassLan) {
      working = working.trimRight();
      if (working.isNotEmpty && !working.endsWith('\n')) working += '\n';
      working += 'route 10.0.0.0 255.0.0.0 net_gateway\n';
      working += 'route 172.16.0.0 255.240.0.0 net_gateway\n';
      working += 'route 192.168.0.0 255.255.0.0 net_gateway\n';
      working += 'route 10.8.0.0 255.255.0.0 vpn_gateway\n';
    }

    if (smartStable) {
      if (!RegExp(r'^\s*tun-mtu\s', multiLine: true, caseSensitive: false).hasMatch(working)) {
        working = working.trimRight();
        if (working.isNotEmpty && !working.endsWith('\n')) working += '\n';
        working += 'tun-mtu 1200\nmssfix 1200\n';
      }
    }

    if (_memoryTier == MemoryTier.low && !smartStable) {
      if (!RegExp(r'^\s*tun-mtu\s', multiLine: true, caseSensitive: false).hasMatch(working)) {
        working = working.trimRight();
        if (working.isNotEmpty && !working.endsWith('\n')) working += '\n';
        working += 'tun-mtu 1280\nmssfix 1200\n';
      }
      if (!RegExp(r'^\s*sndbuf\s', multiLine: true, caseSensitive: false).hasMatch(working)) {
        working = working.trimRight();
        if (working.isNotEmpty && !working.endsWith('\n')) working += '\n';
        working += 'sndbuf 0\nrcvbuf 0\n';
      }
    }

    // 游戏模式 · 减速：仅「全屏游戏模式打开」且选减速时注入 shaper（与日常 VPN 分开）。
    if (_gameTrafficMode == GameModeSpeed.decel && _gameModeOverlayActive) {
      working = working.replaceAll(
        RegExp(r'^\s*shaper\s+.*$', multiLine: true, caseSensitive: false),
        '',
      );
      working = working.trimRight();
      if (working.isNotEmpty && !working.endsWith('\n')) working += '\n';
      working += '# game_mode_decel tier=${_gameDecelTier.name}\n';
      working += 'shaper ${_gameDecelTier.shaperBytesPerSecond}\n';
    }

    // Auto 模式：内置分流（百度直连，其余走 VPN）
    if (routing.mode == TrafficMode.auto) {
      final routes = await _resolveAutoSplitRules();
      if (routes.isNotEmpty) {
        working = working.trimRight();
        if (working.isNotEmpty && !working.endsWith('\n')) working += '\n';
        working += '# traffic_mode_auto\n';
        for (final r in routes) {
          working += 'route $r net_gateway\n';
        }
      }
    }

    // Rule 模式：用户自定义规则内直连，其余走 VPN
    if (routing.mode == TrafficMode.rule) {
      final routes = await _resolveRules(routing.ruleDb);
      if (routes.isNotEmpty) {
        working = working.trimRight();
        if (working.isNotEmpty && !working.endsWith('\n')) working += '\n';
        for (final r in routes) {
          working += 'route $r net_gateway\n';
        }
      }
    }

    final normalized = _ensureTrailingNewline(working.trimRight());
    debugPrint('[OpenVpnPort] Sanitized config length: ${normalized.length}');

    return SanitizedOpenVpnConfig(
      config: normalized,
      username: username,
      password: password,
    );
  }

  @visibleForTesting
  Future<SanitizedOpenVpnConfig> debugSanitizeOpenVpnConfig(String config) async {
    return _sanitizeOpenVpnConfig(
      config,
      const RoutingConfig(bypassLan: false),
      smartStable: false,
    );
  }

  /// Built-in auto-split domains (stub until server rule DB).
  Future<List<String>> _resolveAutoSplitRules() async {
    const domains = ['baidu.com', 'www.baidu.com'];
    final routes = <String>[];
    for (final domain in domains) {
      final ips = await _resolveDomain(domain);
      for (final ip in ips) {
        routes.add('$ip 255.255.255.255');
      }
    }
    return routes;
  }

  /// Resolve custom rules to OpenVPN route format: "network netmask".
  Future<List<String>> _resolveRules(RuleDatabase ruleDb) async {
    // Custom: parse text - CIDR or domain per line
    final lines = ruleDb.customRules
        .split(RegExp(r'\r?\n'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty && !s.startsWith('#'));
    final routes = <String>[];
    for (final line in lines) {
      if (_isCidr(line)) {
        final r = _cidrToRoute(line);
        if (r != null) routes.add(r);
      } else {
        final ips = await _resolveDomain(line);
        for (final ip in ips) {
          routes.add('$ip 255.255.255.255');
        }
      }
    }
    return routes;
  }

  bool _isCidr(String s) => RegExp(r'^\d+\.\d+\.\d+\.\d+/\d+$').hasMatch(s);

  static bool _isValidIpV4(String s) {
    if (s.isEmpty) return false;
    final parts = s.split('.');
    if (parts.length != 4) return false;
    for (final p in parts) {
      final n = int.tryParse(p);
      if (n == null || n < 0 || n > 255) return false;
    }
    return true;
  }

  String? _cidrToRoute(String cidr) {
    final parts = cidr.split('/');
    if (parts.length != 2) return null;
    final base = parts[0].trim();
    final prefix = int.tryParse(parts[1].trim());
    if (prefix == null || prefix < 0 || prefix > 32) return null;
    final mask = _prefixToMask(prefix);
    return '$base $mask';
  }

  String _prefixToMask(int prefix) {
    var mask = 0xFFFFFFFF << (32 - prefix);
    if (prefix == 0) mask = 0;
    final a = (mask >> 24) & 0xFF;
    final b = (mask >> 16) & 0xFF;
    final c = (mask >> 8) & 0xFF;
    final d = mask & 0xFF;
    return '$a.$b.$c.$d';
  }

  Future<Set<String>> _resolveDomain(String domain) async {
    try {
      final ips = await resolveDomainToIpv4(domain);
      return ips;
    } catch (e) {
      debugPrint('[OpenVpnPort] Could not resolve $domain: $e');
      return {};
    }
  }

  model.VpnStatus? _lastStatus;
}

class SanitizedOpenVpnConfig {
  const SanitizedOpenVpnConfig({
    required this.config,
    this.username,
    this.password,
  });

  final String config;
  final String? username;
  final String? password;
}
