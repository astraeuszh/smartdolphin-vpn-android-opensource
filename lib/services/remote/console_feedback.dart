import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../../features/auth/domain/account_session.dart';
import 'console_endpoint.dart';

/// 用户主动反馈（设置 → 向管理员反馈 / 工单）。
const kFeedbackManualErrorCode = 'E0000';

/// Wire-size cap (UTF-8 bytes) kept under the server's 512 KiB tail budget.
const _maxLogBytes = 480 * 1024;
const _maxQueued = 30;

class ConsoleFeedback {
  ConsoleFeedback({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// [kind]: ticket（应用故障工单）/ admin_feedback（向管理员反馈）/ unblock_request（申请解除限制）。
  Future<void> submit({
    required AccountSession session,
    required String errorCode,
    required String message,
    required String logSnapshot,
    String kind = 'ticket',
    List<File> images = const [],
  }) async {
    final info = await PackageInfo.fromPlatform();
    final snapshot = await _appendImageUrls(
      session: session,
      logSnapshot: logSnapshot,
      images: images,
    );
    final body = {
      'uid': session.uid.toString(),
      'error_code': errorCode,
      'message': message,
      'log_snapshot': _capUtf8Tail(snapshot, _maxLogBytes),
      'client': 'android',
      'version': info.version,
      'build': info.buildNumber,
      'device_id': session.deviceId,
      'kind': kind,
    };
    await _send(body);
  }

  /// 工单走同一套 `/api/client/feedback`。结构化文本进 message，运行日志进 log_snapshot。
  Future<void> submitTicket({
    required AccountSession session,
    required String type,
    required String severity,
    required String description,
    String? contactEmail,
    List<File> images = const [],
    String vpnLog = '',
  }) async {
    final contact = contactEmail?.trim();
    final message = StringBuffer()
      ..writeln('[support-ticket]')
      ..writeln('type: $type')
      ..writeln('severity: $severity');
    if (contact != null && contact.isNotEmpty) {
      message.writeln('contact: $contact');
    }
    message.writeln('description: $description');

    final snapshot = StringBuffer()
      ..writeln('--- ticket ---')
      ..writeln(message.toString());
    if (vpnLog.trim().isNotEmpty) {
      snapshot
        ..writeln('--- vpn log (tail) ---')
        ..writeln(vpnLog);
    }

    final info = await PackageInfo.fromPlatform();
    final withImages = await _appendImageUrls(
      session: session,
      logSnapshot: snapshot.toString(),
      images: images,
    );
    await _send({
      'uid': session.uid.toString(),
      'error_code': kFeedbackManualErrorCode,
      'message': _truncateChars(message.toString(), 8000),
      'log_snapshot': _capUtf8Tail(withImages, _maxLogBytes),
      'client': 'android',
      'version': info.version,
      'build': info.buildNumber,
      'device_id': session.deviceId,
      'kind': 'ticket',
    });
  }

  Future<String> _appendImageUrls({
    required AccountSession session,
    required String logSnapshot,
    required List<File> images,
  }) async {
    if (images.isEmpty) return logSnapshot;
    final urls = <String>[];
    for (var i = 0; i < images.length; i++) {
      final url = await uploadAttachment(
        session: session,
        file: images[i],
        filename: 'screenshot-${i + 1}.jpg',
      );
      urls.add(url);
    }
    final buf = StringBuffer(logSnapshot);
    buf.writeln('--- screenshots ---');
    for (final url in urls) {
      buf.writeln(url);
    }
    return buf.toString();
  }

  Future<String> uploadAttachment({
    required AccountSession session,
    required File file,
    required String filename,
  }) async {
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw Exception('截图文件为空');
    }
    if (bytes.length > 4 * 1024 * 1024) {
      throw Exception('截图过大（最大 4MB）');
    }
    final contentType = _guessImageContentType(bytes, filename);
    final uri = Uri.parse('${ConsoleEndpoint.base}/api/client/feedback/attachment');
    final resp = await _client
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'uid': session.uid.toString(),
            'filename': filename,
            'content_type': contentType,
            'data_base64': base64Encode(bytes),
          }),
        )
        .timeout(const Duration(seconds: 60));
    Map<String, dynamic> data;
    try {
      data = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {
      throw Exception('截图上传失败 (HTTP ${resp.statusCode})');
    }
    if (data['ok'] != true) {
      throw Exception((data['error'] as String?) ?? '截图上传失败');
    }
    final url = data['url'] as String?;
    if (url == null || url.isEmpty) {
      throw Exception('截图上传响应无效');
    }
    return url;
  }

  /// Sends a payload; on a network error it is persisted to the offline queue and retried on the
  /// next submit / app launch (previously a failed submission was simply lost).
  Future<void> _send(Map<String, dynamic> body) async {
    await flushPending();
    try {
      await _postFeedback(body);
    } on _FeedbackRejected {
      rethrow; // server explicitly rejected (validation) — do not retry
    } catch (e) {
      await _enqueue(body);
      throw Exception('反馈暂存失败队列，恢复网络后将自动重传：$e');
    }
  }

  Future<void> _postFeedback(Map<String, dynamic> body) async {
    final uri = Uri.parse('${ConsoleEndpoint.base}/api/client/feedback');
    final resp = await _client
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 30));
    Map<String, dynamic> data;
    try {
      data = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {
      // Non-JSON (e.g. 5xx HTML / proxy error) → treat as retryable network failure.
      throw Exception('服务器响应无效 (HTTP ${resp.statusCode})');
    }
    if (data['ok'] != true) {
      throw _FeedbackRejected((data['error'] as String?) ?? '反馈失败');
    }
  }

  // ---- offline queue (file-backed) ----

  Future<File> _queueFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/feedback_queue.jsonl');
  }

  Future<void> _enqueue(Map<String, dynamic> body) async {
    try {
      final f = await _queueFile();
      final lines = (await f.exists()) ? await f.readAsLines() : <String>[];
      lines.add(jsonEncode(body));
      while (lines.length > _maxQueued) {
        lines.removeAt(0);
      }
      await f.writeAsString('${lines.join('\n')}\n');
    } catch (_) {/* best-effort */}
  }

  /// Retries any queued feedback. Safe to call on app launch and before each submit.
  Future<void> flushPending() async {
    File f;
    List<String> lines;
    try {
      f = await _queueFile();
      if (!await f.exists()) return;
      lines = await f.readAsLines();
    } catch (_) {
      return;
    }
    final remaining = <String>[];
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      Map<String, dynamic> body;
      try {
        body = jsonDecode(line) as Map<String, dynamic>;
      } catch (_) {
        continue; // drop corrupt entry
      }
      try {
        await _postFeedback(body);
      } on _FeedbackRejected {
        // server rejected — drop, don't keep retrying forever
      } catch (_) {
        remaining.add(line); // still offline — keep
      }
    }
    try {
      if (remaining.isEmpty) {
        await f.delete();
      } else {
        await f.writeAsString('${remaining.join('\n')}\n');
      }
    } catch (_) {}
  }

  String _guessImageContentType(Uint8List bytes, String filename) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (filename.toLowerCase().endsWith('.png')) return 'image/png';
    if (filename.toLowerCase().endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  String _truncateChars(String value, int maxChars) {
    if (value.length <= maxChars) return value;
    return value.substring(value.length - maxChars);
  }

  /// Caps to the last [maxBytes] UTF-8 bytes (newest content), repairing any split multibyte char.
  String _capUtf8Tail(String value, int maxBytes) {
    final bytes = utf8.encode(value);
    if (bytes.length <= maxBytes) return value;
    final slice = bytes.sublist(bytes.length - maxBytes);
    return utf8.decode(slice, allowMalformed: true);
  }
}

class _FeedbackRejected implements Exception {
  _FeedbackRejected(this.message);
  final String message;
  @override
  String toString() => message;
}
