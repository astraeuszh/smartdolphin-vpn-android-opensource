/// vpn-core directory layout shared with Linux client.
class VpnCoreLayout {
  VpnCoreLayout(this.root);

  final String root;

  String get data => '$root/data';
  String get logs => '$root/logs';
  String get crash => '$root/crash';
  String get cache => '$root/cache';
  String get config => '$root/config';
  String get temp => '$root/temp';

  String logFile(String category, String name) => '$root/$category/$name';

  /// Default feedback log window (not a line cap — all lines within the window are kept).
  static const defaultFeedbackWindow = Duration(minutes: 10);
  static const manualFeedbackWindow = Duration(minutes: 5);
  static const errorFeedbackWindow = Duration(minutes: 10);

  static const userCategories = ['logs/user'];

  static const protectedPrefixes = [
    'data/',
    'config/',
    'crash/',
    'cache/',
    'logs/security/',
    'logs/audit/',
    'logs/runtime/',
    'logs/network/',
    'logs/system/',
    'logs/telemetry/',
  ];

  static const initDirs = [
    'data',
    'logs/security',
    'logs/audit',
    'logs/runtime',
    'logs/network',
    'logs/system',
    'logs/user',
    'logs/telemetry',
    'crash',
    'cache',
    'config',
    'temp',
  ];

  /// Log files merged into feedback snapshots (newest lines within the time window).
  static const feedbackPriority = [
    'crash/crash_meta.json',
    'logs/security/security.log',
    'logs/security/auth.log',
    'logs/runtime/runtime.log',
    'logs/network/connect.log',
    'logs/runtime/dolphin-core.log',
    'logs/system/service.log',
    'logs/user/action.log',
  ];
}
