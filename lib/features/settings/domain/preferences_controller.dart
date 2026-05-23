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
      // 若在异步读取期间用户已改语言，不要用旧快照覆盖内存中的 locale。
      final memLocale = state.localeCode;
      state = loaded;
      if (memLocale != null) {
        state = state.copyWith(localeCode: memLocale);
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

  Future<void> setLocale(String? code) async {
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
