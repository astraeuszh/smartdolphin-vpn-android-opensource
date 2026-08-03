import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../game_mode/domain/game_mode_overlay_provider.dart';
import '../session/domain/session_controller.dart';
import '../session/domain/session_status.dart';
import '../settings/domain/settings_controller.dart';
import 'smart_stable_notifier.dart';
import 'smart_stable_probe.dart';

/// SmartStable 弱网提示：非模态横幅，不阻断 VPN 使用；仅用户点「启动」才重连。
class SmartStableLifecycle extends ConsumerStatefulWidget {
  const SmartStableLifecycle({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SmartStableLifecycle> createState() =>
      _SmartStableLifecycleState();
}

class _SmartStableLifecycleState extends ConsumerState<SmartStableLifecycle>
    with WidgetsBindingObserver {
  bool _busy = false;
  DateTime? _lastResumeHandledAt;
  DateTime? _lastPeriodicProbeAt;
  Timer? _periodicTimer;
  bool _showBanner = false;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _startPeriodicTimer();
  }

  void _startPeriodicTimer() {
    _periodicTimer?.cancel();
    if (!_foreground) return;
    _periodicTimer = Timer.periodic(const Duration(minutes: 10), (_) {
      unawaited(_maybeOffer(fromPeriodic: true));
    });
  }

  @override
  void dispose() {
    _periodicTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _startPeriodicTimer();
    if (state == AppLifecycleState.resumed) {
      unawaited(_maybeOffer());
    }
  }

  Future<void> _maybeOffer({bool fromPeriodic = false}) async {
    if (kIsWeb || !_foreground || _busy || _showBanner) return;
    if (ref.read(gameModeOverlayActiveProvider)) return;
    if (!ref.read(settingsControllerProvider).networkQualityMonitoring) return;
    if (ref.read(sessionControllerProvider).status != SessionStatus.connected) {
      return;
    }

    final now = DateTime.now();
    if (fromPeriodic) {
      if (_lastPeriodicProbeAt != null &&
          now.difference(_lastPeriodicProbeAt!) < const Duration(minutes: 10)) {
        return;
      }
      _lastPeriodicProbeAt = now;
    } else {
      if (_lastResumeHandledAt != null &&
          now.difference(_lastResumeHandledAt!) < const Duration(seconds: 2)) {
        return;
      }
      _lastResumeHandledAt = now;
    }

    final st = ref.read(smartStableProvider);
    if (st.tuningEnabled) return;
    if (st.suppressDeclineUntilNextUserConnect) return;
    if (st.promptCooldownUntil != null &&
        now.isBefore(st.promptCooldownUntil!)) {
      return;
    }

    final bad = await shouldOfferSmartStableProbe();
    if (!bad || !mounted) return;
    if (ref.read(sessionControllerProvider).status != SessionStatus.connected) {
      return;
    }
    setState(() => _showBanner = true);
  }

  Future<void> _onAccept() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _showBanner = false;
    });
    ref.read(smartStableProvider.notifier).enableTuning();
    final navCtx = context;
    if (navCtx.mounted &&
        ref.read(sessionControllerProvider).status == SessionStatus.connected) {
      await ref
          .read(sessionControllerProvider.notifier)
          .reconnectForSmartStable(navCtx);
    }
    if (mounted) setState(() => _busy = false);
  }

  void _onDecline() {
    ref.read(smartStableProvider.notifier).suppressAfterDecline();
    setState(() => _showBanner = false);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_showBanner)
          Positioned(
            left: 12,
            right: 12,
            top: MediaQuery.paddingOf(context).top + 8,
            child: Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(14),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      context.l10n.smartStableTitle,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      context.l10n.smartStablePrompt,
                      style: const TextStyle(fontSize: 13, height: 1.35),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: _onDecline,
                          child: Text(context.l10n.smartStableDecline),
                        ),
                        FilledButton(
                          onPressed: _busy ? null : _onAccept,
                          child: Text(context.l10n.smartStableStart),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
