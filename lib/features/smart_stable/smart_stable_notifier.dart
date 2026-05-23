import 'package:flutter_riverpod/flutter_riverpod.dart';

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
          suppressDeclineUntilNextUserConnect ?? this.suppressDeclineUntilNextUserConnect,
      promptCooldownUntil: promptCooldownUntil ?? this.promptCooldownUntil,
    );
  }
}

class SmartStableNotifier extends StateNotifier<SmartStableState> {
  SmartStableNotifier() : super(const SmartStableState());

  static const _afterAcceptCooldown = Duration(minutes: 5);
  static const _afterReconnectCooldown = Duration(seconds: 45);
  static const _afterDeclineDebounce = Duration(seconds: 4);

  void enableTuning() {
    state = state.copyWith(
      tuningEnabled: true,
      suppressDeclineUntilNextUserConnect: false,
      promptCooldownUntil: DateTime.now().add(_afterAcceptCooldown),
    );
  }

  void disableTuning() => state = state.copyWith(tuningEnabled: false);

  /// 用户点「暂不需要」：直到下次从断开状态发起连接前不再问；仅短 debounce 防连点。
  void suppressAfterDecline() {
    state = state.copyWith(
      suppressDeclineUntilNextUserConnect: true,
      promptCooldownUntil: DateTime.now().add(_afterDeclineDebounce),
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
  return SmartStableNotifier();
});
