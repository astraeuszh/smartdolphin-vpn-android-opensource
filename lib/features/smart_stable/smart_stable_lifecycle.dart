import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app.dart';
import '../game_mode/domain/game_mode_overlay_provider.dart';
import '../session/domain/session_controller.dart';
import '../session/domain/session_status.dart';
import '../settings/domain/settings_controller.dart';
import 'smart_stable_notifier.dart';
import 'smart_stable_probe.dart';

/// 仅前台 SmartStable 探测 + 弹窗（游戏模式、冷却、已启用调优时不弹）。
class SmartStableLifecycle extends ConsumerStatefulWidget {
  const SmartStableLifecycle({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SmartStableLifecycle> createState() =>
      _SmartStableLifecycleState();
}

class _SmartStableLifecycleState extends ConsumerState<SmartStableLifecycle>
    with WidgetsBindingObserver {
  bool _dialogInFlight = false;
  DateTime? _lastResumeHandledAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_onResumed());
    }
  }

  Future<void> _onResumed() async {
    if (kIsWeb) {
      return;
    }
    if (ref.read(gameModeOverlayActiveProvider)) {
      return;
    }
    if (!ref.read(settingsControllerProvider).networkQualityMonitoring) {
      return;
    }

    final session = ref.read(sessionControllerProvider);
    if (session.status != SessionStatus.connected) {
      return;
    }

    final now = DateTime.now();
    if (_lastResumeHandledAt != null &&
        now.difference(_lastResumeHandledAt!) < const Duration(seconds: 2)) {
      return;
    }
    _lastResumeHandledAt = now;

    final st = ref.read(smartStableProvider);
    if (st.tuningEnabled) {
      return;
    }
    if (st.suppressDeclineUntilNextUserConnect) {
      return;
    }
    if (st.promptCooldownUntil != null && now.isBefore(st.promptCooldownUntil!)) {
      return;
    }

    final bad = await shouldOfferSmartStableProbe();
    if (!bad || !mounted) {
      return;
    }

    if (ref.read(sessionControllerProvider).status != SessionStatus.connected) {
      return;
    }

    if (_dialogInFlight) {
      return;
    }
    _dialogInFlight = true;
    try {
      final navCtx = ref.read(navigatorKeyProvider).currentContext;
      if (navCtx == null || !navCtx.mounted) {
        return;
      }

      final accepted = await showDialog<bool>(
        context: navCtx,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('SmartStable'),
          content: const Text(
            '当前网络环境极度异常（可能处于隧道、山林、高铁、劣质 WiFi 等场景），是否启动 Smart Dolphin VPN 自研的 SmartStable 服务以优化连接稳定性？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('暂不需要'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('启动'),
            ),
          ],
        ),
      );

      if (!mounted) {
        return;
      }
      if (accepted == true) {
        ref.read(smartStableProvider.notifier).enableTuning();
        final session = ref.read(sessionControllerProvider);
        if (session.status == SessionStatus.connected && navCtx.mounted) {
          unawaited(
            ref.read(sessionControllerProvider.notifier).reconnectForSmartStable(
                  navCtx,
                ),
          );
        }
      } else if (accepted == false) {
        ref.read(smartStableProvider.notifier).suppressAfterDecline();
      }
    } finally {
      _dialogInFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
