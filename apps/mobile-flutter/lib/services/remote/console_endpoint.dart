/// Smart Dolphin 控制台 / API 基址。
class ConsoleEndpoint {
  ConsoleEndpoint._();

  static const String defaultUrl = 'https://api.smartdolphin.top';

  static String get base {
    const fromEnv = String.fromEnvironment('SMARTDOLPHIN_CONSOLE_URL');
    if (fromEnv.isNotEmpty) {
      return fromEnv.replaceAll(RegExp(r'/+$'), '');
    }
    return defaultUrl;
  }
}
