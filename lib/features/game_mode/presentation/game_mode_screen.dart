import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../services/haptics/haptics_service.dart';
import '../../../widgets/connect_control.dart';
import '../../servers/domain/server_providers.dart';
import '../../session/domain/session_controller.dart';
import '../../session/domain/session_status.dart';
import '../../session/presentation/countdown.dart';
import '../domain/game_mode_controller.dart';
import '../domain/game_mode_speed.dart';
import 'widgets/game_decel_tier_section.dart';

Future<void> _safeDisconnect(WidgetRef ref) async {
  try {
    await ref.read(sessionControllerProvider.notifier).disconnect();
  } catch (e, st) {
    debugPrint('[GameModeScreen] disconnect error: $e');
    debugPrintStack(stackTrace: st);
  }
}

/// 游戏模式：中间连接 + 底部分段（不展示服务器卡片，选节点在首页）。
class GameModeScreen extends ConsumerWidget {
  const GameModeScreen({
    super.key,
    required this.onExit,
  });

  final VoidCallback onExit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = context.l10n;
    final speed = ref.watch(gameModeControllerProvider);
    final session = ref.watch(sessionControllerProvider);
    final mq = MediaQuery.of(context);

    final isPreparing = session.status == SessionStatus.preparing;
    final isConnecting = session.status == SessionStatus.connecting;
    final isAttemptCancelable = isPreparing || isConnecting;
    final isBusy = isAttemptCancelable;
    final isConnected = session.status == SessionStatus.connected;
    final buttonState = isConnected
        ? ConnectButtonVisualState.active
        : isAttemptCancelable
            ? ConnectButtonVisualState.connecting
            : ConnectButtonVisualState.idle;

    final drawerW = math.max(200.0, mq.size.width * 0.5);

    return Material(
      color: cs.surface,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              cs.surface,
              Color.lerp(cs.surface, cs.primary, 0.06)!,
              cs.surfaceContainerHighest.withValues(alpha: 0.4),
            ],
            stops: const [0.0, 0.45, 1.0],
          ),
        ),
        child: SafeArea(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            drawer: Drawer(
              width: drawerW,
              backgroundColor: Colors.white,
              elevation: 0,
              child: ColoredBox(
                color: Colors.white,
                child: SafeArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                        child: Text(
                          l10n.gameModeSettingsTitle,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                          children: [
                            const GameDecelTierSection(
                              variant: GameDecelTierSectionVariant.drawer,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            body: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      IconButton.filledTonal(
                        tooltip: l10n.gameModeBackTooltip,
                        onPressed: onExit,
                        style: IconButton.styleFrom(
                          foregroundColor: cs.onSurface,
                        ),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                      const Spacer(),
                      Builder(
                        builder: (ctx) => IconButton.filledTonal(
                          tooltip: l10n.gameModeMenuTooltip,
                          onPressed: () => Scaffold.of(ctx).openDrawer(),
                          style: IconButton.styleFrom(
                            foregroundColor: cs.onSurface,
                          ),
                          icon: const Icon(Icons.menu_rounded),
                        ),
                      ),
                    ],
                  ),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ConnectControl(
                          enabled: !isBusy || isAttemptCancelable,
                          isActive: isConnected,
                          isLoading: isBusy,
                          visualState: buttonState,
                          label: isConnected
                              ? l10n.disconnect
                              : isAttemptCancelable
                                  ? l10n.statusConnecting
                                  : l10n.connect,
                          statusText: isAttemptCancelable
                              ? l10n.tapToCancel
                              : null,
                          onTap: () async {
                            await ref.read(hapticsServiceProvider).impact();
                            if (!context.mounted) return;
                            if (isConnected) {
                              unawaited(_safeDisconnect(ref));
                            } else if (isAttemptCancelable) {
                              unawaited(_safeDisconnect(ref));
                            } else {
                              final server =
                                  ref.read(selectedServerProvider);
                              if (server == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(l10n.pleaseSelectServer),
                                  ),
                                );
                                return;
                              }
                              await ref
                                  .read(sessionControllerProvider.notifier)
                                  .connect(context: context, server: server);
                            }
                          },
                        ),
                        const SizedBox(height: 16),
                        if (isConnected)
                          const SessionCountdown()
                        else
                          Text(
                            l10n.unlockSecureAccess,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: cs.onSurface.withValues(alpha: 0.6),
                            ),
                            textAlign: TextAlign.center,
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: 16 + mq.padding.bottom,
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest
                            .withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: cs.outline.withValues(alpha: 0.12),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: SegmentedButton<GameModeSpeed>(
                          style: SegmentedButton.styleFrom(
                            selectedBackgroundColor: Color.lerp(
                              cs.primary,
                              cs.surface,
                              0.82,
                            ),
                            selectedForegroundColor: cs.onSurface,
                            foregroundColor:
                                cs.onSurface.withValues(alpha: 0.75),
                            side: BorderSide.none,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 14,
                            ),
                          ),
                          segments: [
                            ButtonSegment(
                              value: GameModeSpeed.decel,
                              label: Text(l10n.gameModeDecelMode),
                              icon: Icon(
                                Icons.slow_motion_video_rounded,
                                size: 22,
                                color: speed == GameModeSpeed.decel
                                    ? cs.primary
                                    : null,
                              ),
                            ),
                            ButtonSegment(
                              value: GameModeSpeed.accel,
                              label: Text(l10n.gameModeAccelMode),
                              icon: Icon(
                                Icons.bolt_rounded,
                                size: 22,
                                color: speed == GameModeSpeed.accel
                                    ? cs.primary
                                    : null,
                              ),
                            ),
                          ],
                          selected: {speed},
                          onSelectionChanged: (s) async {
                            unawaited(
                              ref.read(hapticsServiceProvider).selection(),
                            );
                            await ref
                                .read(gameModeControllerProvider.notifier)
                                .setSpeed(s.first);
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
