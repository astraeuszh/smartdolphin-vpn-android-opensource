import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'console_update.dart';
import '../../l10n/app_localizations.dart';

Future<void> checkAndPromptForUpdate(
  BuildContext context, {
  bool automatic = false,
}) async {
  final info = await PackageInfo.fromPlatform();
  final l10n = AppLocalizations.of(context);
  final service = ConsoleUpdate();
  UpdateCheckResult update;
  try {
    update = await service.check(
      version: info.version,
      build: info.buildNumber,
    );
  } catch (_) {
    if (automatic || !context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.updateCheckFailed),
        content: Text(l10n.updateDownloadFailed),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.commonOk),
          ),
        ],
      ),
    );
    return;
  }
  if (!update.isNewerThan(info.version)) {
    if (automatic || !context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.updateUpToDate),
        content: Text(l10n.updateCurrentRelease(info.version)),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.commonOk),
          ),
        ],
      ),
    );
    return;
  }
  final preferences = await SharedPreferences.getInstance();
  if (automatic &&
      !update.forceUpdate &&
      preferences.getString('dismissed_update') == update.versionName) {
    return;
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: !update.forceUpdate,
    builder: (dialogContext) {
      var downloading = false;
      var status = '';
      var progress = 0.0;
      Timer? progressTimer;
      return PopScope(
        canPop: !update.forceUpdate,
        child: StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(
              update.forceUpdate ? l10n.updateRequired : l10n.updateAvailable,
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.updateVersionAvailable(update.versionName)),
                if (update.releaseNotes.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(update.releaseNotes),
                ],
                if (status.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(status, style: Theme.of(context).textTheme.bodySmall),
                ],
                if (downloading) ...[
                  const SizedBox(height: 10),
                  LinearProgressIndicator(
                      value: progress > 0 ? progress : null),
                ],
              ],
            ),
            actions: [
              if (!update.forceUpdate)
                TextButton(
                  onPressed: downloading
                      ? null
                      : () async {
                          await preferences.setString(
                            'dismissed_update',
                            update.versionName,
                          );
                          if (dialogContext.mounted) {
                            Navigator.of(dialogContext).pop();
                          }
                        },
                  child: Text(l10n.updateNotNow),
                ),
              FilledButton.icon(
                onPressed: downloading
                    ? null
                    : () async {
                        if (update.forceUpdate && progress >= 1) {
                          await service.openBackgroundInstaller();
                          return;
                        }
                        setDialogState(() {
                          downloading = true;
                          status = l10n.updateDownloading;
                        });
                        try {
                          if (update.forceUpdate) {
                            await service.enqueueBackground(update);
                            progressTimer?.cancel();
                            progressTimer = Timer.periodic(
                              const Duration(seconds: 1),
                              (_) async {
                                final current = await service.backgroundState();
                                if (!dialogContext.mounted) {
                                  progressTimer?.cancel();
                                  return;
                                }
                                final ratio = current.total > 0
                                    ? current.received / current.total
                                    : 0.0;
                                setDialogState(() {
                                  progress = current.status == 'successful'
                                      ? 1.0
                                      : ratio.clamp(0.0, 1.0);
                                  downloading = current.status == 'pending' ||
                                      current.status == 'running' ||
                                      current.status == 'paused';
                                  status = current.status == 'successful'
                                      ? l10n.updateInstallerOpen
                                      : current.status == 'failed'
                                          ? l10n.updateDownloadFailed
                                          : '${l10n.updateDownloading} ${(progress * 100).round()}%';
                                });
                                if (current.status == 'successful' ||
                                    current.status == 'failed') {
                                  progressTimer?.cancel();
                                }
                              },
                            );
                          } else {
                            await service.downloadAndInstall(
                              update,
                              onProgress: (received, total) {
                                if (!dialogContext.mounted) return;
                                setDialogState(() {
                                  progress = total > 0 ? received / total : 0;
                                  final percent = total > 0
                                      ? (progress * 100).clamp(0, 100).round()
                                      : null;
                                  status = percent == null
                                      ? l10n.updateDownloading
                                      : '${l10n.updateDownloading} $percent%';
                                });
                              },
                            );
                          }
                          if (!dialogContext.mounted) return;
                          if (!update.forceUpdate) {
                            Navigator.of(dialogContext).pop();
                          }
                        } catch (_) {
                          if (!dialogContext.mounted) return;
                          setDialogState(() {
                            downloading = false;
                            status = l10n.updateDownloadFailed;
                          });
                        }
                      },
                icon: downloading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.system_update_alt_rounded),
                label: Text(
                    update.forceUpdate && progress >= 1
                        ? l10n.updateNow
                        : update.forceUpdate
                            ? l10n.updateNow
                            : l10n.updateDownload),
              ),
            ],
          ),
        ),
      );
    },
  );
}
