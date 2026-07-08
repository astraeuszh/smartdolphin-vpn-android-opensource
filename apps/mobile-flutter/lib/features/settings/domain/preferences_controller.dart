import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/storage/prefs.dart';
import 'preferences_state.dart';

const _prefsKey = 'settings.preferences';

class PreferencesController extends StateNotifier<PreferencesState> {
  PreferencesController(this._ref) : super(const PreferencesState()) {
    _hydrate();
  }

  final Ref _ref;
  final Completer<void> _hydrated = Completer<void>();
  var _localeChangedByUser = false;

  Future<void> get ready => _hydrated.future;

  Future<void> _hydrate() async {
    final prefs = await _ref.read(prefsStoreProvider.future);
    final raw = prefs.getString(_prefsKey);
    if (raw == null) {
      if (!_hydrated.isCompleted) {
        _hydrated.complete();
      }
      return;
    }
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final loaded = PreferencesState.fromJson(data);
      if (_localeChangedByUser) {
        state = loaded.copyWith(localeCode: state.localeCode);
      } else {
        state = loaded;
      }
    } catch (_) {
      // ignore corrupt preferences
    }
    if (!_hydrated.isCompleted) {
      _hydrated.complete();
    }
  }

  Future<void> _persist() async {
    final prefs = await _ref.read(prefsStoreProvider.future);
    await prefs.setString(_prefsKey, jsonEncode(state.toJson()));
  }

  Future<void> toggleAutoServerSwitch(bool enabled) async {
    state = state.copyWith(autoServerSwitch: enabled);
    await _persist();
  }

  Future<void> toggleHaptics(bool enabled) async {
    state = state.copyWith(hapticsEnabled: enabled);
    await _persist();
  }

  Future<void> setAutoReconnect(bool enabled) async {
    state = state.copyWith(autoReconnect: enabled);
    await _persist();
  }

  /// Dolphin-Core transport: 'reality' | 'hysteria2' | 'wireguard'.
  Future<void> setCoreProtocol(String protocol) async {
    state = state.copyWith(coreProtocol: protocol);
    await _persist();
  }

  Future<void> setLocale(String? code) async {
    _localeChangedByUser = true;
    state = state.copyWith(localeCode: code);
    await _persist();
  }

  Future<void> setPrivacyPolicyAccepted(bool accepted) async {
    state = state.copyWith(privacyPolicyAccepted: accepted);
    await _persist();
  }

  Future<void> setOnboardingCompleted(bool completed) async {
    state = state.copyWith(onboardingCompleted: completed);
    await _persist();
  }
}

final preferencesControllerProvider =
    StateNotifierProvider<PreferencesController, PreferencesState>((ref) {
  return PreferencesController(ref);
});

final preferencesReadyProvider = FutureProvider<void>((ref) async {
  final notifier = ref.watch(preferencesControllerProvider.notifier);
  await notifier.ready;
});
