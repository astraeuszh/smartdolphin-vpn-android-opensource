import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/storage/prefs.dart';

/// SmartStable：弱网调优（MTU / mssfix）+ 仅前台询问。
class SmartStableState {
  const SmartStableState({
    this.tuningEnabled = false,

    /// 用户点「暂不需要」后，直到下一次 **用户发起的** 从断开状态连接前不再弹窗。
    this.suppressDeclineUntilNextUserConnect = false,

    /// 任意一次弹窗关闭后，短时间内不再弹（防 resume 连弹、重连后立即再弹）。
    this.promptCooldownUntil,
  });

  final bool tuningEnabled;
  final bool suppressDeclineUntilNextUserConnect;
  final DateTime? promptCooldownUntil;

  SmartStableState copyWith({
    bool? tuningEnabled,
    bool? suppressDeclineUntilNextUserConnect,
    DateTime? promptCooldownUntil,
  }) {
    return SmartStableState(
      tuningEnabled: tuningEnabled ?? this.tuningEnabled,
      suppressDeclineUntilNextUserConnect:
          suppressDeclineUntilNextUserConnect ??
              this.suppressDeclineUntilNextUserConnect,
      promptCooldownUntil: promptCooldownUntil ?? this.promptCooldownUntil,
    );
  }
}

class SmartStableNotifier extends StateNotifier<SmartStableState> {
  SmartStableNotifier(this._ref) : super(const SmartStableState()) {
    _restore();
  }

  final Ref _ref;

  static const _afterAcceptCooldown = Duration(minutes: 5);
  static const _afterReconnectCooldown = Duration(seconds: 45);
  static const _afterDeclineCooldown = Duration(minutes: 30);
  static const _prefsKey = 'smart_stable_tuning_enabled';

  /// Restore the persisted tuning state so it survives an app restart (users
  /// used to think it stayed on while the MTU silently reverted to default).
  Future<void> _restore() async {
    try {
      final store = await _ref.read(prefsStoreProvider.future);
      if (store.getBool(_prefsKey) && mounted) {
        state = state.copyWith(tuningEnabled: true);
      }
    } catch (_) {}
  }

  Future<void> _persist(bool enabled) async {
    try {
      final store = await _ref.read(prefsStoreProvider.future);
      await store.setBool(_prefsKey, enabled);
    } catch (_) {}
  }

  void enableTuning() {
    state = state.copyWith(
      tuningEnabled: true,
      suppressDeclineUntilNextUserConnect: false,
      promptCooldownUntil: DateTime.now().add(_afterAcceptCooldown),
    );
    unawaited(_persist(true));
  }

  void disableTuning() {
    state = state.copyWith(tuningEnabled: false);
    unawaited(_persist(false));
  }

  /// 用户点「暂不需要」：3 小时内不再弹，除非用户断开 VPN 后重新连接。
  void suppressAfterDecline() {
    state = state.copyWith(
      suppressDeclineUntilNextUserConnect: true,
      promptCooldownUntil: DateTime.now().add(_afterDeclineCooldown),
    );
  }

  /// 用户从 **断开** 状态发起普通连接时调用，允许下次弱网时再次询问。
  void clearDeclineSuppressForNewUserConnect() {
    if (!state.suppressDeclineUntilNextUserConnect) return;
    state = state.copyWith(suppressDeclineUntilNextUserConnect: false);
  }

  /// SmartStable 触发的断开/重连前后，避免紧接着又弹窗。
  void armReconnectCooldown() {
    state = state.copyWith(
      promptCooldownUntil: DateTime.now().add(_afterReconnectCooldown),
    );
  }
}

final smartStableProvider =
    StateNotifierProvider<SmartStableNotifier, SmartStableState>((ref) {
  return SmartStableNotifier(ref);
});
