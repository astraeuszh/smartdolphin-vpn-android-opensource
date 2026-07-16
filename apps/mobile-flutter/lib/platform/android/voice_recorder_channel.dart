import 'package:flutter/services.dart';

import '../../core/platform/runtime_platform.dart';

class VoiceRecorderChannel {
  VoiceRecorderChannel._();

  static const _channel = MethodChannel('smartdolphin/voice_recorder');

  static Future<bool> start() async {
    if (!isAndroidNative) return false;
    return await _channel.invokeMethod<bool>('start') ?? false;
  }

  static Future<String?> stop() async {
    if (!isAndroidNative) return null;
    return _channel.invokeMethod<String>('stop');
  }

  /// Android MediaRecorder's instantaneous microphone peak, normalized by the
  /// caller. It is available only while an active recording is running.
  static Future<int> amplitude() async {
    if (!isAndroidNative) return 0;
    return await _channel.invokeMethod<int>('amplitude') ?? 0;
  }

  static Future<void> cancel() async {
    if (!isAndroidNative) return;
    await _channel.invokeMethod<void>('cancel');
  }

  static Future<void> openMedia(String path) async {
    if (!isAndroidNative) return;
    await _channel.invokeMethod<void>('openMedia', {'path': path});
  }

  static Future<String?> saveToDownloads(String path, String fileName) async {
    if (!isAndroidNative) return null;
    return _channel.invokeMethod<String>('saveToDownloads', {
      'path': path,
      'fileName': fileName,
    });
  }

  static Future<void> playVoice(String path, {double speed = 1}) async {
    if (!isAndroidNative) return;
    await _channel
        .invokeMethod<void>('playVoice', {'path': path, 'speed': speed});
  }
}
