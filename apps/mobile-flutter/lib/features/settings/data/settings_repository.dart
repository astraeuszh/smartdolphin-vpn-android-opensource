import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/storage/prefs.dart';
import '../domain/advanced_settings_config.dart';
import '../domain/auto_connect_rules.dart';
import '../domain/log_config.dart';
import '../domain/protocol_config.dart';
import '../domain/routing_config.dart';
import '../domain/split_tunnel_config.dart';

class SettingsRepository {
  SettingsRepository(this._prefs);

  final PrefsStore _prefs;

  static const _protocolKey = 'settings_protocol';
  static const _splitTunnelKey = 'settings_split_tunnel';
  static const _routingKey = 'settings_routing';
  static const _logKey = 'settings_log';
  static const _autoConnectKey = 'settings_auto_connect';
  static const _batterySaverKey = 'settings_battery_saver';
  static const _networkQualityKey = 'settings_network_quality';
  static const _preciseSessionTimerKey = 'settings_precise_session_timer';
  static const _advancedKey = 'settings_advanced';
  static const _appearanceAccentKey = 'settings_accent';

  ProtocolConfig loadProtocol() {
    final jsonString = _prefs.getString(_protocolKey);
    return ProtocolConfig.fromJson(_decode(jsonString));
  }

  Future<void> saveProtocol(ProtocolConfig config) async {
    await _prefs.setString(_protocolKey, json.encode(config.toJson()));
  }

  SplitTunnelConfig loadSplitTunnel() {
    final jsonString = _prefs.getString(_splitTunnelKey);
    return SplitTunnelConfig.fromJson(_decode(jsonString));
  }

  Future<void> saveSplitTunnel(SplitTunnelConfig config) async {
    await _prefs.setString(_splitTunnelKey, json.encode(config.toJson()));
  }

  RoutingConfig loadRouting() {
    final jsonString = _prefs.getString(_routingKey);
    return RoutingConfig.fromJson(_decode(jsonString));
  }

  Future<void> saveRouting(RoutingConfig config) async {
    var toSave = config;
    if (config.ruleDb.customRules.length > 8192) {
      toSave = config.copyWith(
        ruleDb: config.ruleDb.copyWith(customRules: ''),
      );
    }
    await _prefs.setString(_routingKey, json.encode(toSave.toJson()));
  }

  LogConfig loadLog() {
    final jsonString = _prefs.getString(_logKey);
    return LogConfig.fromJson(_decode(jsonString));
  }

  Future<void> saveLog(LogConfig config) async {
    await _prefs.setString(_logKey, json.encode(config.toJson()));
  }

  AutoConnectRules loadAutoConnect() {
    final jsonString = _prefs.getString(_autoConnectKey);
    return AutoConnectRules.fromJson(_decode(jsonString));
  }

  Future<void> saveAutoConnect(AutoConnectRules rules) async {
    await _prefs.setString(_autoConnectKey, json.encode(rules.toJson()));
  }

  bool loadBatterySaver() =>
      _prefs.getBool(_batterySaverKey, defaultValue: false);

  Future<void> saveBatterySaver(bool value) async {
    await _prefs.setBool(_batterySaverKey, value);
  }

  bool loadNetworkQuality() =>
      _prefs.getBool(_networkQualityKey, defaultValue: true);

  Future<void> saveNetworkQuality(bool value) async {
    await _prefs.setBool(_networkQualityKey, value);
  }

  bool loadPreciseSessionTimer() =>
      _prefs.getBool(_preciseSessionTimerKey, defaultValue: false);

  Future<void> savePreciseSessionTimer(bool value) async {
    await _prefs.setBool(_preciseSessionTimerKey, value);
  }

  String? loadAccent() => _prefs.getString(_appearanceAccentKey);

  Future<void> saveAccent(String name) =>
      _prefs.setString(_appearanceAccentKey, name);

  AdvancedSettingsConfig loadAdvanced() {
    final jsonString = _prefs.getString(_advancedKey);
    return AdvancedSettingsConfig.fromJson(_decode(jsonString));
  }

  Future<void> saveAdvanced(AdvancedSettingsConfig config) async {
    await _prefs.setString(_advancedKey, json.encode(config.toJson()));
  }

  Map<String, dynamic>? _decode(String? jsonString) {
    if (jsonString == null) return null;
    try {
      return json.decode(jsonString) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}

final settingsRepositoryProvider = Provider<SettingsRepository?>((ref) {
  final prefsAsync = ref.watch(prefsStoreProvider);
  return prefsAsync.whenOrNull(data: SettingsRepository.new);
});
