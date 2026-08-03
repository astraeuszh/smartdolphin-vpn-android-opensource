import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:web_socket_channel/io.dart';

import '../../features/auth/domain/account_session.dart';
import '../../features/settings/domain/support_chat_models.dart';
import 'client_request_headers.dart';
import 'console_endpoint.dart';

MediaType supportMediaTypeForPath(String path) {
  final extension = path.split('.').last.toLowerCase();
  return switch (extension) {
    'jpg' || 'jpeg' => MediaType('image', 'jpeg'),
    'png' => MediaType('image', 'png'),
    'gif' => MediaType('image', 'gif'),
    'webp' => MediaType('image', 'webp'),
    'heic' => MediaType('image', 'heic'),
    'heif' => MediaType('image', 'heif'),
    'avif' => MediaType('image', 'avif'),
    'bmp' => MediaType('image', 'bmp'),
    'mp4' => MediaType('video', 'mp4'),
    'mov' => MediaType('video', 'quicktime'),
    'mkv' => MediaType('video', 'x-matroska'),
    'webm' => MediaType('video', 'webm'),
    '3gp' => MediaType('video', '3gpp'),
    'avi' => MediaType('video', 'x-msvideo'),
    'm4v' => MediaType('video', 'x-m4v'),
    'm4a' => MediaType('audio', 'mp4'),
    'aac' => MediaType('audio', 'aac'),
    'mp3' => MediaType('audio', 'mpeg'),
    'wav' => MediaType('audio', 'wav'),
    'ogg' => MediaType('audio', 'ogg'),
    'opus' => MediaType('audio', 'opus'),
    _ => MediaType('application', 'octet-stream'),
  };
}

class SupportChatApi {
  SupportChatApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const _bases = [
    'https://api.smartdolphinvpn.com',
    'https://smartdolphinvpn.com',
  ];

  Stream<void> events(AccountSession session) async* {
    var retrySeconds = 1;
    while (true) {
      for (final base in _bases) {
        IOWebSocketChannel? channel;
        try {
          final uri = Uri.parse(
            '${base.replaceFirst('https://', 'wss://')}/api/auth/support/events',
          );
          channel = IOWebSocketChannel.connect(
            uri,
            headers: await _headers(session, json: false),
            pingInterval: const Duration(seconds: 30),
            connectTimeout: const Duration(seconds: 8),
          );
          await channel.ready;
          retrySeconds = 1;
          await for (final raw in channel.stream) {
            try {
              final body = jsonDecode('$raw');
              if (body is Map && body['type'] == 'support_changed') {
                yield null;
              }
            } catch (_) {}
          }
        } catch (_) {
          // Try the alternate API host, then reconnect with bounded backoff.
        } finally {
          await channel?.sink.close();
        }
      }
      await Future<void>.delayed(Duration(seconds: retrySeconds));
      retrySeconds = retrySeconds < 30 ? retrySeconds * 2 : 30;
    }
  }

  Future<http.Response> _postWithFallback(
    String path, {
    required Map<String, String> headers,
    required String body,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    Object? lastError;
    http.Response? lastResponse;
    for (final base in _bases) {
      try {
        final response = await _client
            .post(Uri.parse('$base$path'), headers: headers, body: body)
            .timeout(timeout);
        lastResponse = response;
        if ((response.statusCode >= 200 && response.statusCode < 300) ||
            const {400, 401, 403, 409, 413, 422, 429}
                .contains(response.statusCode)) {
          return response;
        }
      } on Object catch (error) {
        lastError = error;
      }
    }
    if (lastResponse != null) return lastResponse;
    throw FormatException('support_network: $lastError');
  }

  Future<http.Response> _deleteWithFallback(
    String path, {
    required Map<String, String> headers,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    Object? lastError;
    http.Response? lastResponse;
    for (final base in _bases) {
      try {
        final response = await _client
            .delete(Uri.parse('$base$path'), headers: headers)
            .timeout(timeout);
        lastResponse = response;
        if ((response.statusCode >= 200 && response.statusCode < 300) ||
            const {400, 401, 403, 409, 413, 422, 429}
                .contains(response.statusCode)) {
          return response;
        }
      } on Object catch (error) {
        lastError = error;
      }
    }
    if (lastResponse != null) return lastResponse;
    throw FormatException('support_network: $lastError');
  }

  Future<Map<String, String>> _headers(AccountSession session,
          {bool json = true}) =>
      ClientRequestHeaders.standard(
        bearerToken: session.sessionToken,
        json: json,
      );

  bool isUnauthorized(Object error) =>
      error is FormatException &&
      (error.message == 'support_unauthorized' ||
          error.message == 'support_forbidden');

  void _requireSuccess(
      http.Response response, Map<String, dynamic> body, String fallback) {
    if (response.statusCode == 401) {
      throw const FormatException('support_unauthorized');
    }
    if (response.statusCode == 403) {
      throw const FormatException('support_forbidden');
    }
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        body['ok'] != true) {
      throw FormatException('${body['error'] ?? fallback}');
    }
  }

  Future<List<SupportConversation>> conversations(
      AccountSession session) async {
    final response = await _getWithFallback(
      '/api/auth/support/conversations',
      headers: await _headers(session, json: false),
    );
    final body = _jsonObject(response.body, 'support_load');
    _requireSuccess(response, body, 'support_load');
    return (body['conversations'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((item) =>
            SupportConversation.fromRemote(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<List<SupportMessage>> messages(
      AccountSession session, String conversationId) async {
    final response = await _getWithFallback(
      '/api/auth/support/conversations/$conversationId/messages',
      headers: await _headers(session, json: false),
    );
    final body = _jsonObject(response.body, 'support_messages');
    _requireSuccess(response, body, 'support_messages');
    return (body['messages'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((item) => SupportMessage.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<void> create(AccountSession session, String conversationId) async {
    final response = await _postWithFallback(
      '/api/auth/support/conversations',
      headers: await _headers(session),
      body: jsonEncode({'id': conversationId}),
      timeout: const Duration(seconds: 15),
    );
    final body = _jsonObject(response.body, 'support_create');
    _requireSuccess(response, body, 'support_create');
  }

  Future<void> setTyping(
      AccountSession session, String conversationId, bool typing) async {
    await _client
        .post(
          Uri.parse('${ConsoleEndpoint.base}/api/auth/support/typing'),
          headers: await _headers(session),
          body:
              jsonEncode({'conversationId': conversationId, 'typing': typing}),
        )
        .timeout(const Duration(seconds: 8));
  }

  Future<http.Response> _getWithFallback(
    String path, {
    required Map<String, String> headers,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    Object? lastError;
    http.Response? lastResponse;
    for (final base in _bases) {
      try {
        final response = await _client
            .get(Uri.parse('$base$path'), headers: headers)
            .timeout(timeout);
        lastResponse = response;
        if ((response.statusCode >= 200 && response.statusCode < 300) ||
            const {400, 401, 403, 409, 413, 422, 429}
                .contains(response.statusCode)) {
          return response;
        }
      } on Object catch (error) {
        lastError = error;
      }
    }
    if (lastResponse != null) return lastResponse;
    throw FormatException('support_network: $lastError');
  }

  Future<SupportMessage> send(
      AccountSession session, String conversationId, SupportMessage message,
      {String? attachmentId}) async {
    final response = await _postWithFallback(
      '/api/auth/support/conversations/$conversationId/messages',
      headers: await _headers(session),
      body: jsonEncode({
        'clientMessageId': message.id,
        'kind': message.kind.name,
        'body': message.value,
        'attachmentId': attachmentId ?? '',
        'durationMs': message.durationMs,
      }),
    );
    final body = _jsonObject(response.body, 'support_send');
    _requireSuccess(response, body, 'support_send');
    final remote = Map<String, dynamic>.from(body['message'] as Map);
    return SupportMessage(
      id: remote['id'] as String? ?? message.id,
      createdAt: (remote['createdAt'] as num?)?.toInt() ?? message.createdAt,
      kind: message.kind,
      value: message.value,
      durationMs: message.durationMs,
      attachmentId: attachmentId ?? '',
    );
  }

  Future<void> recall(
      AccountSession session, String conversationId, String messageId) async {
    final response = await _client
        .delete(
          Uri.parse(
              '${ConsoleEndpoint.base}/api/auth/support/conversations/$conversationId/messages/$messageId'),
          headers: await _headers(session, json: false),
        )
        .timeout(const Duration(seconds: 15));
    final body = _jsonObject(response.body, 'support_recall');
    _requireSuccess(response, body, 'support_recall');
  }

  Future<void> deleteConversation(
      AccountSession session, String conversationId) async {
    final response = await _deleteWithFallback(
      '/api/auth/support/conversations/$conversationId',
      headers: await _headers(session, json: false),
    );
    final body = _jsonObject(response.body, 'support_delete');
    _requireSuccess(response, body, 'support_delete');
  }

  Future<void> renameConversation(
      AccountSession session, String conversationId, String title) async {
    final response = await _client
        .patch(
          Uri.parse(
              '${ConsoleEndpoint.base}/api/auth/support/conversations/$conversationId'),
          headers: await _headers(session),
          body: jsonEncode({'title': title}),
        )
        .timeout(const Duration(seconds: 15));
    final body = _jsonObject(response.body, 'support_rename');
    _requireSuccess(response, body, 'support_rename');
  }

  Future<String> upload(AccountSession session, File file) async {
    final size = await file.length();
    if (size <= 0 || size > 1024 * 1024 * 1024) {
      throw const FormatException('upload_too_large');
    }
    final contentType = supportMediaTypeForPath(file.path);
    http.Response? response;
    Object? lastError;
    for (final base in _bases) {
      final uploadClient = http.Client();
      try {
        final request = http.MultipartRequest(
          'POST',
          Uri.parse('$base/api/auth/support/upload'),
        )
          ..headers.addAll(await _headers(session, json: false))
          ..files.add(await http.MultipartFile.fromPath(
            'file',
            file.path,
            contentType: contentType,
          ));
        final candidate = await http.Response.fromStream(
          await uploadClient.send(request).timeout(const Duration(minutes: 20)),
        );
        response = candidate;
        if (!((candidate.statusCode >= 200 && candidate.statusCode < 300) ||
            const {400, 401, 403, 409, 413, 422, 429}
                .contains(candidate.statusCode))) {
          response = null;
        }
      } on Object catch (error) {
        lastError = error;
      } finally {
        uploadClient.close();
      }
      if (response != null) break;
    }
    if (response == null) throw FormatException('support_upload: $lastError');
    final body = _jsonObject(response.body, 'support_upload');
    final attachment = body['attachment'];
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        body['ok'] != true ||
        attachment is! Map) {
      throw FormatException('${body['error'] ?? 'support_upload'}');
    }
    return attachment['id'] as String;
  }

  Map<String, dynamic> _jsonObject(String source, String code) {
    try {
      final decoded = jsonDecode(source);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // The API can return an HTML error body through a reverse proxy. Keep
      // it as a typed app failure instead of leaking a JSON parser exception.
    }
    throw FormatException(code);
  }

  Future<File> download(AccountSession session, String attachmentId,
      String fileName, Directory cache) async {
    final safeName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final file = File('${cache.path}/$attachmentId-$safeName');
    final partial = File('${file.path}.part');
    Object? lastError;
    for (final base in _bases) {
      final request = http.Request(
        'GET',
        Uri.parse('$base/api/auth/support/attachments/$attachmentId'),
      )..headers.addAll(await _headers(session, json: false));
      IOSink? sink;
      try {
        final response = await _client.send(request).timeout(
              const Duration(seconds: 30),
            );
        if (response.statusCode < 200 || response.statusCode >= 300) {
          await response.stream.drain<void>();
          if (const {400, 401, 403, 409, 413, 422, 429}
              .contains(response.statusCode)) {
            throw const FormatException('support_download');
          }
          continue;
        }
        await partial.parent.create(recursive: true);
        sink = partial.openWrite();
        var received = 0;
        await for (final chunk in response.stream.timeout(
          const Duration(minutes: 20),
        )) {
          received += chunk.length;
          if (received > 1024 * 1024 * 1024) {
            throw const FormatException('download_too_large');
          }
          sink.add(chunk);
        }
        await sink.flush();
        await sink.close();
        sink = null;
        if (received <= 0) throw const FormatException('support_download');
        if (await file.exists()) await file.delete();
        return partial.rename(file.path);
      } on Object catch (error) {
        lastError = error;
        await sink?.close();
        if (await partial.exists()) await partial.delete();
        if (error is FormatException &&
            const {'support_download', 'download_too_large'}
                .contains(error.message)) {
          rethrow;
        }
      }
    }
    throw FormatException('support_download: $lastError');
  }
}
