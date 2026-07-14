import 'dart:convert';

import '../../../services/storage/prefs.dart';
import '../domain/support_chat_models.dart';

class SupportChatRepository {
  SupportChatRepository(this._prefs);

  final PrefsStore _prefs;
  static const _key = 'support_chat.conversations.v1';

  List<SupportConversation> load() {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final data = jsonDecode(raw) as List<dynamic>;
      return data
          .whereType<Map>()
          .map((item) =>
              SupportConversation.fromJson(Map<String, dynamic>.from(item)))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(List<SupportConversation> conversations) =>
      _prefs.setString(
        _key,
        jsonEncode(conversations
            .map((conversation) => conversation.toJson())
            .toList()),
      );
}
