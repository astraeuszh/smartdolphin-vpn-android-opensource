import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/storage/prefs.dart';
import 'data_usage_state.dart';

const _usageKey = 'usage.state';
const _bytesPerSecondEstimate = 256 * 1024; // ~2 Mbps

class DataUsageController extends StateNotifier<DataUsageState> {
  DataUsageController(this._ref) : super(DataUsageState.initial()) {
    _hydrate();
  }

  final Ref _ref;

  Future<void> _hydrate() async {
    final prefs = await _ref.read(prefsStoreProvider.future);
    final raw = prefs.getString(_usageKey);
    if (raw == null) {
      return;
    }
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      state = DataUsageState.fromJson(data);
    } catch (_) {
      state = DataUsageState.initial();
    }
  }

  Future<void> _persist() async {
    final prefs = await _ref.read(prefsStoreProvider.future);
    await prefs.setString(_usageKey, jsonEncode(state.toJson()));
  }

  Future<void> recordTickUsage() async {
    state = state.copyWith(
      usedBytes: state.usedBytes + _bytesPerSecondEstimate,
      lastUpdated: DateTime.now().toUtc(),
    );
    await _persist();
  }

  Future<void> addUsageBytes(int bytes) async {
    if (bytes <= 0) return;
    final prev = state.usedBytes;
    final newUsed = prev + bytes;
    final limit = state.monthlyLimitBytes;
    var pending90 = state.pendingTraffic90Dialog;
    var warned90 = state.traffic90Warned;

    if (limit != null && limit > 0) {
      final prevRatio = prev / limit;
      final newRatio = newUsed / limit;
      if (!warned90 && prevRatio < 0.9 && newRatio >= 0.9) {
        pending90 = true;
        warned90 = true;
      }
    }

    state = state.copyWith(
      usedBytes: newUsed,
      lastUpdated: DateTime.now().toUtc(),
      pendingTraffic90Dialog: pending90,
      traffic90Warned: warned90,
    );
    await _persist();
  }

  Future<void> setMonthlyLimit(int? bytes) async {
    state = state.copyWith(monthlyLimitBytes: bytes);
    await _persist();
  }

  Future<void> syncUsedFromServerGb(double usedGb) async {
    final serverUsed = (usedGb * 1024 * 1024 * 1024).round();
    state = state.copyWith(
      usedBytes: serverUsed,
      lastUpdated: DateTime.now().toUtc(),
    );
    await _persist();
  }

  Future<void> resetUsage() async {
    state = DataUsageState(
      periodStart: DateTime.now().toUtc(),
      usedBytes: 0,
      monthlyLimitBytes: state.monthlyLimitBytes,
      lastUpdated: DateTime.now().toUtc(),
      pendingTraffic90Dialog: false,
      traffic90Warned: false,
    );
    await _persist();
  }

  Future<void> clearTraffic90Dialog() async {
    if (!state.pendingTraffic90Dialog) return;
    state = state.copyWith(pendingTraffic90Dialog: false);
    await _persist();
  }
}

final dataUsageControllerProvider =
    StateNotifierProvider<DataUsageController, DataUsageState>((ref) {
  return DataUsageController(ref);
});
