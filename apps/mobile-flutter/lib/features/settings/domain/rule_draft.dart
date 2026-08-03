import 'package:flutter_riverpod/flutter_riverpod.dart';

/// In-memory SDRL draft — tracks unsaved edits outside the editor screen.
class RuleDraftState {
  const RuleDraftState({
    this.text = '',
    this.savedFileName = '',
    this.savedSnapshot = '',
    this.pendingReconnect = false,
  });

  final String text;

  /// Empty = never saved to a named file; temp_* = ephemeral label.
  final String savedFileName;
  final String savedSnapshot;
  final bool pendingReconnect;

  bool get isDirty => text != savedSnapshot;

  String get displayName =>
      savedFileName.isEmpty ? RuleDraftNotifier.tempLabel() : savedFileName;

  RuleDraftState copyWith({
    String? text,
    String? savedFileName,
    String? savedSnapshot,
    bool? pendingReconnect,
  }) =>
      RuleDraftState(
        text: text ?? this.text,
        savedFileName: savedFileName ?? this.savedFileName,
        savedSnapshot: savedSnapshot ?? this.savedSnapshot,
        pendingReconnect: pendingReconnect ?? this.pendingReconnect,
      );
}

class RuleDraftNotifier extends StateNotifier<RuleDraftState> {
  RuleDraftNotifier() : super(const RuleDraftState());

  static String tempLabel() => 'temp_${DateTime.now().millisecondsSinceEpoch}';

  void syncFromPersisted({
    required String text,
    required String savedFileName,
  }) {
    state = RuleDraftState(
      text: text,
      savedFileName: savedFileName,
      savedSnapshot: text,
    );
  }

  void updateText(String text) {
    state = state.copyWith(text: text);
  }

  void markSaved({
    required String text,
    required String fileName,
    bool pendingReconnect = false,
  }) {
    state = RuleDraftState(
      text: text,
      savedFileName: fileName,
      savedSnapshot: text,
      pendingReconnect: pendingReconnect,
    );
  }

  void clearPendingReconnect() {
    if (!state.pendingReconnect) return;
    state = state.copyWith(pendingReconnect: false);
  }

  void discardDraft() {
    state = RuleDraftState(
      text: state.savedSnapshot,
      savedFileName: state.savedFileName,
      savedSnapshot: state.savedSnapshot,
    );
  }
}

final ruleDraftProvider =
    StateNotifierProvider<RuleDraftNotifier, RuleDraftState>(
  (ref) => RuleDraftNotifier(),
);
