enum SupportMessageKind { text, image, video, voice }

class SupportMessage {
  const SupportMessage({
    required this.id,
    required this.createdAt,
    required this.kind,
    required this.value,
    this.mine = true,
    this.durationMs = 0,
    this.attachmentId = '',
    this.failed = false,
    this.mediaLoading = false,
  });

  final String id;
  final int createdAt;
  final SupportMessageKind kind;
  final String value;
  final bool mine;
  final int durationMs;
  final String attachmentId;
  final bool failed;
  /// The message is authoritative, but its media file is still being cached.
  /// Keeping this state on the same message prevents media bubbles from
  /// disappearing while polling reconciles server history.
  final bool mediaLoading;

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt,
        'kind': kind.name,
        'value': value,
        'mine': mine,
        'durationMs': durationMs,
        'attachmentId': attachmentId,
        'failed': failed,
        'mediaLoading': mediaLoading,
      };

  factory SupportMessage.fromJson(Map<String, dynamic> json) {
    final kindName = json['kind'] as String? ?? 'text';
    return SupportMessage(
      id: json['id'] as String? ?? '${DateTime.now().microsecondsSinceEpoch}',
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      kind: SupportMessageKind.values.firstWhere(
        (item) => item.name == kindName,
        orElse: () => SupportMessageKind.text,
      ),
      value: json['value'] as String? ?? '',
      mine: json['mine'] as bool? ?? true,
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
      attachmentId: json['attachmentId'] as String? ?? '',
      failed: json['failed'] as bool? ?? false,
      mediaLoading: json['mediaLoading'] as bool? ?? false,
    );
  }
}

class SupportConversation {
  const SupportConversation({
    required this.id,
    required this.createdAt,
    required this.messages,
    this.updatedAt = 0,
    this.messageCount = 0,
  });

  final String id;
  final int createdAt;
  final List<SupportMessage> messages;
  final int updatedAt;
  final int messageCount;

  String get title {
    final texts =
        messages.where((message) => message.kind == SupportMessageKind.text);
    if (texts.isEmpty || texts.first.value.trim().isEmpty) {
      return 'New conversation';
    }
    return texts.first.value.trim();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'messageCount': messageCount,
        'messages': messages.map((message) => message.toJson()).toList(),
      };

  factory SupportConversation.fromJson(Map<String, dynamic> json) {
    final rawMessages = json['messages'] as List<dynamic>? ?? const [];
    return SupportConversation(
      id: json['id'] as String? ?? '${DateTime.now().microsecondsSinceEpoch}',
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
      messageCount: (json['messageCount'] as num?)?.toInt() ??
          rawMessages.length,
      messages: rawMessages
          .whereType<Map>()
          .map((entry) =>
              SupportMessage.fromJson(Map<String, dynamic>.from(entry)))
          .toList(),
    );
  }

  factory SupportConversation.fromRemote(Map<String, dynamic> json) =>
      SupportConversation(
        id: json['id'] as String? ?? '',
        createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
        updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
        messageCount: (json['messageCount'] as num?)?.toInt() ?? 0,
        messages: const [],
      );
}
