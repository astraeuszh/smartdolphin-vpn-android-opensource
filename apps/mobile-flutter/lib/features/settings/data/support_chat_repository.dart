import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../../services/storage/prefs.dart';
import '../../auth/domain/account_session.dart';
import '../domain/support_chat_models.dart';

class SupportChatRepository {
  SupportChatRepository(this._prefs, {required this.accountKey});

  final PrefsStore _prefs;
  final String accountKey;
  static const _legacyKey = 'support_chat.conversations.v1';

  String get _key => 'support_chat.conversations.v2.$accountKey';

  factory SupportChatRepository.forSession(
    PrefsStore prefs,
    AccountSession session,
  ) =>
      SupportChatRepository(
        prefs,
        accountKey: accountKeyFor(session),
      );

  static String accountKeyFor(AccountSession session) {
    final identity = session.publicUid.trim().isNotEmpty
        ? 'public-${session.publicUid.trim()}'
        : session.uid > 0
            ? 'uid-${session.uid}'
            : 'user-${session.username.trim().toLowerCase()}';
    return identity.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  }

  Future<List<SupportConversation>> load() async {
    // v1 was shared by every account. It cannot be migrated safely because it
    // contains no owner identity, so discard it instead of leaking one user's
    // conversations into another account.
    if (_prefs.getString(_legacyKey) != null) {
      await _prefs.remove(_legacyKey);
    }
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

  Future<Directory> mediaCacheDirectory() async {
    final root = await getApplicationSupportDirectory();
    final directory =
        Directory('${root.path}/support-media-cache/$accountKey');
    await directory.create(recursive: true);
    return directory;
  }

  Future<void> clear() async {
    await _prefs.remove(_key);
    await _prefs.remove(_legacyKey);
    final root = await getApplicationSupportDirectory();
    final directory =
        Directory('${root.path}/support-media-cache/$accountKey');
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  static Future<void> clearAccount(AccountSession session) async {
    final prefs = await PrefsStore.create();
    await SupportChatRepository.forSession(prefs, session).clear();
  }
}
