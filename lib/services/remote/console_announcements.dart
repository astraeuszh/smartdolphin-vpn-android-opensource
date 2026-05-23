import 'dart:convert';

import 'package:http/http.dart' as http;

import 'console_endpoint.dart';

class ConsoleAnnouncement {
  const ConsoleAnnouncement({
    required this.id,
    required this.title,
    required this.body,
    this.published = false,
    this.updatedAt = 0,
  });

  final int id;
  final String title;
  final String body;
  final bool published;
  final int updatedAt;

  factory ConsoleAnnouncement.fromJson(Map<String, dynamic> data) {
    return ConsoleAnnouncement(
      id: _asInt(data['id']),
      title: (data['title'] as String?)?.trim() ?? '',
      body: (data['body'] as String?)?.trim() ?? '',
      published: data['published'] == true,
      updatedAt: _asInt(data['updated_at']),
    );
  }

  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }
}

class ConsoleAnnouncements {
  ConsoleAnnouncements({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<List<ConsoleAnnouncement>> fetchPublished() async {
    final uri = Uri.parse('${ConsoleEndpoint.base}/api/client/announcements');
    final resp = await _client.get(uri).timeout(const Duration(seconds: 18));
    Map<String, dynamic> data;
    try {
      data = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {
      throw Exception('服务器响应无效');
    }
    if (data['ok'] != true) {
      throw Exception((data['error'] as String?) ?? '公告加载失败');
    }
    final rows = data['announcements'];
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((row) => ConsoleAnnouncement.fromJson(Map<String, dynamic>.from(row)))
        .where((row) => row.published && row.title.isNotEmpty)
        .toList();
  }
}
