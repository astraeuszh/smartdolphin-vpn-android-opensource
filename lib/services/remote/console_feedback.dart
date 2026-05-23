import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../../features/auth/domain/account_session.dart';
import 'console_endpoint.dart';

/// 用户主动反馈（设置 → 向管理员反馈 / 工单）。
const kFeedbackManualErrorCode = 'E0000';

class ConsoleFeedback {
  ConsoleFeedback({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<void> submit({
    required AccountSession session,
    required String errorCode,
    required String message,
    required String logSnapshot,
  }) async {
    final info = await PackageInfo.fromPlatform();
    final body = {
      'uid': session.uid,
      'error_code': errorCode,
      'message': message,
      'log_snapshot': logSnapshot,
      'client': 'android',
      'version': info.version,
      'build': info.buildNumber,
      'device_id': session.deviceId,
    };
    await _postFeedback(body);
  }

  /// 工单走同一套 `/api/client/feedback`，在 message / log_snapshot 中结构化描述。
  Future<void> submitTicket({
    required AccountSession session,
    required String type,
    required String severity,
    required String description,
    String? contactEmail,
    List<String> imageBase64 = const [],
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
    if (imageBase64.isNotEmpty) {
      snapshot.writeln('--- images (${imageBase64.length}) ---');
      for (var i = 0; i < imageBase64.length; i++) {
        snapshot.writeln('[image:$i] ${imageBase64[i]}');
      }
    }

    final info = await PackageInfo.fromPlatform();
    await _postFeedback({
      'uid': session.uid,
      'error_code': kFeedbackManualErrorCode,
      'message': _truncate(message.toString(), 8000),
      'log_snapshot': _truncate(snapshot.toString(), 64000),
      'client': 'android',
      'version': info.version,
      'build': info.buildNumber,
      'device_id': session.deviceId,
    });
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
      throw Exception('服务器响应无效');
    }
    if (data['ok'] != true) {
      throw Exception((data['error'] as String?) ?? '反馈失败');
    }
  }

  String _truncate(String value, int maxChars) {
    if (value.length <= maxChars) return value;
    return value.substring(value.length - maxChars);
  }
}
