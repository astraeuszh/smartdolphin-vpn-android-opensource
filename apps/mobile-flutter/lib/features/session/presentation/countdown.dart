import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/session/session_limits.dart';
import '../../../l10n/app_localizations.dart';
import '../../settings/domain/settings_controller.dart';
import '../domain/session_controller.dart';
import '../domain/session_state.dart';
import '../domain/session_status.dart';
import '../../../services/time/session_clock_provider.dart';

/// Local session timer. Keep the default cadence low: a 60fps timer keeps the
/// UI thread awake and is visible in Android battery reports during long VPN sessions.
class SessionCountdown extends ConsumerStatefulWidget {
  const SessionCountdown({super.key});

  @override
  ConsumerState<SessionCountdown> createState() => _SessionCountdownState();
}

class _SessionCountdownState extends ConsumerState<SessionCountdown> {
  Timer? _timer;
  Duration _display = Duration.zero;
  int _anchorElapsed = 0;
  DateTime _wallAnchor = DateTime.now();
  int? _startElapsedMs;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _bootstrapAnchor(int startElapsedMs,
      {required bool precise}) async {
    final clock = ref.read(sessionClockProvider);
    _anchorElapsed = await clock.elapsedRealtime();
    _wallAnchor = DateTime.now();
    _startElapsedMs = startElapsedMs;
    _tickDisplay();
    _timer?.cancel();
    final tick = precise
        ? const Duration(milliseconds: 250)
        : const Duration(seconds: 1);
    _timer = Timer.periodic(tick, (_) => _tickDisplay());
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    _startElapsedMs = null;
    if (_display != Duration.zero) {
      setState(() => _display = Duration.zero);
    }
  }

  void _tickDisplay() {
    final start = _startElapsedMs;
    if (start == null || !mounted) return;
    final wallElapsed = DateTime.now().difference(_wallAnchor);
    final elapsedMs = (_anchorElapsed - start) + wallElapsed.inMilliseconds;
    final next = Duration(milliseconds: elapsedMs.clamp(0, 0x7FFFFFFF));
    if (next != _display) {
      setState(() => _display = next);
    }
  }

  String _formatElapsed(
      AppLocalizations l10n, Duration duration, bool precise) {
    if (precise) {
      final ms = duration.inMilliseconds % 1000;
      var t = duration.inMilliseconds ~/ 1000;
      final sec = t % 60;
      t ~/= 60;
      final min = t % 60;
      t ~/= 60;
      final hour = t % 24;
      final day = t ~/ 24;
      return l10n.sessionElapsedLabel(
        l10n.sessionElapsedParts(
          day: day,
          hour: hour,
          minute: min,
          second: sec,
          millisecond: ms,
        ),
      );
    }

    final capped = _capSessionDuration(duration);
    final totalSeconds = capped.inSeconds;
    final days = totalSeconds ~/ 86400;
    final rem = totalSeconds % 86400;
    final hours = rem ~/ 3600;
    final minutes = (rem % 3600) ~/ 60;
    final seconds = rem % 60;
    return l10n.sessionElapsedLabel(
      l10n.sessionElapsedParts(
        day: days > 0 ? days : null,
        hour: hours,
        minute: minutes,
        second: seconds,
      ),
    );
  }

  Duration _capSessionDuration(Duration raw) {
    final cap = kMaxSessionWallDuration;
    if (raw.isNegative) return Duration.zero;
    return raw > cap ? cap : raw;
  }

  @override
  Widget build(BuildContext context) {
    final precise = ref.watch(settingsControllerProvider).preciseSessionTimer;

    ref.listen<SessionState>(sessionControllerProvider, (prev, next) {
      final connected =
          next.status == SessionStatus.connected && next.startElapsedMs != null;
      final wasConnected = prev?.status == SessionStatus.connected &&
          prev?.startElapsedMs != null;
      if (connected && !wasConnected) {
        unawaited(_bootstrapAnchor(next.startElapsedMs!, precise: precise));
      } else if (!connected && wasConnected) {
        _stop();
      }
    });

    final state = ref.watch(sessionControllerProvider);
    if (state.status == SessionStatus.connected &&
        state.startElapsedMs != null &&
        _startElapsedMs == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _startElapsedMs == null) {
          unawaited(_bootstrapAnchor(state.startElapsedMs!, precise: precise));
        }
      });
    }

    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final display = state.status == SessionStatus.connected
        ? _formatElapsed(l10n, _display, precise)
        : l10n.sessionElapsedLabel(
            l10n.sessionElapsedParts(
              day: precise ? 0 : null,
              hour: 0,
              minute: 0,
              second: 0,
              millisecond: precise ? 0 : null,
            ),
          );

    return Text(
      display,
      style: theme.textTheme.bodyLarge?.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
      ),
    );
  }
}
