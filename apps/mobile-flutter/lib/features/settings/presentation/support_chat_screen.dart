import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../../../platform/android/voice_recorder_channel.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/storage/prefs.dart';
import '../../../services/remote/support_chat_api.dart';
import '../../auth/domain/account_session.dart';
import '../../auth/domain/auth_controller.dart';
import '../data/support_chat_repository.dart';
import '../domain/support_chat_models.dart';

class SupportChatScreen extends ConsumerStatefulWidget {
  const SupportChatScreen({super.key});

  @override
  ConsumerState<SupportChatScreen> createState() => _SupportChatScreenState();
}

class _SupportChatScreenState extends ConsumerState<SupportChatScreen>
    with WidgetsBindingObserver {
  final _message = TextEditingController();
  final List<SupportConversation> _conversations = [];
  SupportChatRepository? _repository;
  String? _activeConversationId;
  bool _loading = true;
  bool _voiceMode = false;
  bool _recording = false;
  bool _cancelVoice = false;
  double _voiceDragDistance = 0;
  DateTime? _voiceStartedAt;
  bool _sending = false;
  bool _typingActive = false;
  bool _typingRequestInFlight = false;
  Timer? _typingTimer;
  Timer? _messagePollTimer;
  bool _syncing = false;
  int _pollCycle = 0;
  DateTime? _lastSupportAuthRecovery;
  final _api = SupportChatApi();

  List<SupportMessage> get _messages => _active?.messages ?? const [];
  SupportConversation? get _active => _conversations
      .where((conversation) => conversation.id == _activeConversationId)
      .firstOrNull;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restore();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _typingTimer?.cancel();
    _messagePollTimer?.cancel();
    _message.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_syncRemote());
      _startMessagePolling();
    } else {
      _messagePollTimer?.cancel();
      _messagePollTimer = null;
    }
  }

  void _startMessagePolling() {
    _messagePollTimer?.cancel();
    _messagePollTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) {
        if (_isPageActive) unawaited(_syncRemote());
      },
    );
  }

  bool get _isPageActive {
    if (!mounted) return false;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      return false;
    }
    return ModalRoute.of(context)?.isCurrent ?? true;
  }

  void _typingChanged(String value) {
    final current = _active;
    final session = ref.read(authControllerProvider).session;
    if (current == null || session == null) return;
    final shouldType = value.trim().isNotEmpty;
    if (shouldType != _typingActive && !_typingRequestInFlight) {
      _typingActive = shouldType;
      unawaited(_setTyping(session, current.id, shouldType));
    }
    _typingTimer?.cancel();
    if (shouldType) {
      _typingTimer = Timer(const Duration(seconds: 2), () {
        if (_typingActive) {
          _typingActive = false;
          unawaited(_setTyping(session, current.id, false));
        }
      });
    }
  }

  Future<void> _setTyping(
      AccountSession session, String conversationId, bool typing) async {
    if (_typingRequestInFlight) return;
    _typingRequestInFlight = true;
    try {
      await _api.setTyping(session, conversationId, typing);
    } catch (_) {
      // Typing is advisory only. A failure must not retry in a tight loop or
      // affect the message's actual send path.
    } finally {
      _typingRequestInFlight = false;
    }
  }

  Future<void> _restore() async {
    final session = ref.read(authControllerProvider).session;
    if (session == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final repository = SupportChatRepository.forSession(
      await PrefsStore.create(),
      session,
    );
    final conversations = await repository.load();
    if (!mounted) return;
    setState(() {
      _repository = repository;
      _conversations.addAll(conversations);
      _activeConversationId =
          conversations.isEmpty ? null : conversations.first.id;
      _loading = false;
    });
    await _syncRemote(force: true);
    if (!mounted) return;
    _ensureActiveConversation();
    if (WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      _startMessagePolling();
    }
  }

  void _ensureActiveConversation() {
    if (_activeConversationId != null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    setState(() {
      _conversations.insert(
        0,
        SupportConversation(
          id: '$now',
          createdAt: now,
          updatedAt: now,
          messages: const [],
        ),
      );
      _activeConversationId = '$now';
    });
    _persist();
  }

  Future<void> _persist() async {
    final repository = _repository;
    if (repository == null) return;
    await repository.save(_conversations);
  }

  void _append(SupportMessage message) {
    final current = _active;
    if (current == null) return;
    final updated = SupportConversation(
      id: current.id,
      createdAt: current.createdAt,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      messageCount: current.messages.length + 1,
      messages: [...current.messages, message],
    );
    setState(() {
      final index = _conversations.indexWhere((item) => item.id == current.id);
      _conversations[index] = updated;
    });
    _persist();
  }

  void _replaceMessage(String draftId, SupportMessage? replacement) {
    final current = _active;
    if (current == null) return;
    final messages = [...current.messages];
    final index = messages.indexWhere((item) => item.id == draftId);
    if (index < 0) return;
    if (replacement == null) {
      messages.removeAt(index);
    } else {
      messages[index] = replacement;
    }
    final updated = SupportConversation(
      id: current.id,
      createdAt: current.createdAt,
      updatedAt: current.updatedAt,
      messageCount: messages.length,
      messages: messages,
    );
    setState(() {
      final conversationIndex =
          _conversations.indexWhere((item) => item.id == current.id);
      if (conversationIndex >= 0) _conversations[conversationIndex] = updated;
    });
    unawaited(_persist());
  }

  Future<void> _syncRemote({
    bool allowAuthRecovery = true,
    bool force = false,
  }) async {
    if (!force && !_isPageActive) return;
    if (_syncing || _sending) return;
    final session = ref.read(authControllerProvider).session;
    if (session == null || session.sessionToken.isEmpty) return;
    _syncing = true;
    try {
      final remote = await _api.conversations(session);
      final remoteIds = remote.map((item) => item.id).toSet();
      // The server list is authoritative. Only failed local drafts are kept;
      // conversations removed with an account/server-side deletion must not
      // remain visible forever from SharedPreferences.
      final unresolvedLocalDrafts = _conversations
          .where((item) =>
              !remoteIds.contains(item.id) &&
              (item.messages.any((message) => message.failed) ||
                  (item.id == _activeConversationId &&
                      item.messages.isEmpty)))
          .toList();
      _conversations.removeWhere((item) => !remoteIds.contains(item.id));
      for (final conversation in remote) {
        final localIndex =
            _conversations.indexWhere((item) => item.id == conversation.id);
        final cached = localIndex < 0 ? null : _conversations[localIndex];
        final changed = cached == null ||
            cached.updatedAt != conversation.updatedAt ||
            cached.messageCount != conversation.messageCount;
        // The list response includes updatedAt/messageCount. Fetch message
        // bodies only for changed conversations (and periodically reconcile
        // the active one), instead of N extra requests every ten seconds.
        final reconcileActive = conversation.id == _activeConversationId &&
            _pollCycle % 6 == 0;
        if (!changed && !reconcileActive) continue;
        final remoteMessages = await _api.messages(session, conversation.id);
        final messages = <SupportMessage>[];
        for (final message in remoteMessages) {
          final local = localIndex < 0
              ? const <SupportMessage>[]
              : _conversations[localIndex].messages;
          messages.add(await _mergeRemoteMessage(session, local, message));
        }
        final index =
            _conversations.indexWhere((item) => item.id == conversation.id);
        final local = index < 0
            ? const <SupportMessage>[]
            : _conversations[index].messages;
        final unresolved = local.where((draft) =>
            draft.failed &&
            !messages.any(
              (remote) =>
                  remote.kind == draft.kind &&
                  (remote.kind == SupportMessageKind.text
                      ? remote.value == draft.value
                      : (remote.createdAt - draft.createdAt).abs() < 30000),
            ));
        final hydrated = SupportConversation(
          id: conversation.id,
          createdAt: conversation.createdAt,
          updatedAt: conversation.updatedAt,
          messageCount: conversation.messageCount,
          messages: [...messages, ...unresolved],
        );
        if (index < 0) {
          _conversations.add(hydrated);
        } else {
          _conversations[index] = hydrated;
        }
      }
      _conversations.addAll(unresolvedLocalDrafts);
      _pollCycle++;
      _conversations.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (!_conversations
          .any((item) => item.id == _activeConversationId)) {
        _activeConversationId = _conversations.firstOrNull?.id;
      }
      if (mounted) setState(() {});
      await _persist();
    } catch (error) {
      // Local conversations remain available as drafts while offline.
      if (allowAuthRecovery && _canRecoverSupportAuth(error)) {
        _lastSupportAuthRecovery = DateTime.now();
        _syncing = false;
        await ref
            .read(authControllerProvider.notifier)
            .setForegroundPresence(true);
        if (ref.read(authControllerProvider).session == null) {
          if (mounted) {
            setState(() {
              _conversations.clear();
              _activeConversationId = null;
            });
            Navigator.of(context).popUntil((route) => route.isFirst);
          }
          return;
        }
        await _syncRemote(allowAuthRecovery: false, force: true);
        return;
      }
    } finally {
      _syncing = false;
    }
  }

  bool _canRecoverSupportAuth(Object error) {
    final last = _lastSupportAuthRecovery;
    return _api.isUnauthorized(error) &&
        (last == null ||
            DateTime.now().difference(last) >= const Duration(minutes: 1));
  }

  Future<SupportMessage> _mergeRemoteMessage(
    AccountSession session,
    List<SupportMessage> local,
    SupportMessage remote,
  ) async {
    final sameId = local.where((item) => item.id == remote.id).firstOrNull;
    final localMedia = sameId ??
        local
            .where((item) =>
                item.mine == remote.mine &&
                item.kind == remote.kind &&
                item.kind != SupportMessageKind.text &&
                (item.createdAt - remote.createdAt).abs() < 30000)
            .firstOrNull;

    // A user just sent this file. Do not replace its stable local path with a
    // server-side filename while the next poll runs.
    if (localMedia != null && File(localMedia.value).existsSync()) {
      return SupportMessage(
        id: remote.id,
        createdAt: remote.createdAt,
        kind: remote.kind,
        value: localMedia.value,
        mine: remote.mine,
        durationMs: remote.durationMs,
        attachmentId: remote.attachmentId,
      );
    }
    return _cacheRemoteMedia(session, remote);
  }

  Future<SupportMessage> _cacheRemoteMedia(
      AccountSession session, SupportMessage message) async {
    if (message.kind == SupportMessageKind.text ||
        message.attachmentId.isEmpty ||
        File(message.value).existsSync()) {
      return message;
    }
    try {
      final repository = _repository;
      if (repository == null) return message;
      final cache = await repository.mediaCacheDirectory();
      final safeName =
          message.value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final cached = File('${cache.path}/${message.attachmentId}-$safeName');
      if (cached.existsSync()) {
        return SupportMessage(
          id: message.id,
          createdAt: message.createdAt,
          kind: message.kind,
          value: cached.path,
          mine: message.mine,
          durationMs: message.durationMs,
          attachmentId: message.attachmentId,
          failed: message.failed,
        );
      }
      final file = await _api.download(
        session,
        message.attachmentId,
        message.value,
        cache,
      );
      return SupportMessage(
        id: message.id,
        createdAt: message.createdAt,
        kind: message.kind,
        value: file.path,
        mine: message.mine,
        durationMs: message.durationMs,
        attachmentId: message.attachmentId,
        failed: message.failed,
        mediaLoading: false,
      );
    } catch (_) {
      // The server has already confirmed this message. Keep a deterministic
      // placeholder and retry caching on the next poll instead of removing it.
      return SupportMessage(
        id: message.id,
        createdAt: message.createdAt,
        kind: message.kind,
        value: message.value,
        mine: message.mine,
        durationMs: message.durationMs,
        attachmentId: message.attachmentId,
        failed: message.failed,
        mediaLoading: true,
      );
    }
  }

  Future<void> _send() async {
    final value = _message.text.trim();
    if (value.isEmpty || _sending) return;
    _message.clear();
    await _sendMessage(_newMessage(SupportMessageKind.text, value));
  }

  Future<void> _sendMessage(SupportMessage draft) async {
    final current = _active;
    if (current == null) {
      if (mounted) {
        _showSendError(const FormatException('support_conversation_missing'));
      }
      return;
    }
    AccountSession? session = ref.read(authControllerProvider).session;
    try {
      // A valid local token is enough to send. A forced account refresh here
      // used to make every message depend on an unrelated status request and
      // could fail before the POST ever reached the server.
      if (session == null || session.sessionToken.isEmpty) {
        await ref
            .read(authControllerProvider.notifier)
            .refreshSession(force: true);
        session = ref.read(authControllerProvider).session;
      }
      if (session == null || session.sessionToken.isEmpty) {
        throw const FormatException('support_session_missing');
      }
      if (session.isMuted) {
        throw const FormatException('account_muted');
      }
      _append(draft);
      if (mounted) setState(() => _sending = true);
      await _api.create(session, current.id);
      String attachmentId = '';
      if (draft.kind != SupportMessageKind.text) {
        attachmentId = await _api.upload(session, File(draft.value));
      }
      final sent = await _api.send(session, current.id, draft,
          attachmentId: attachmentId);
      _replaceMessage(draft.id, sent);
    } catch (error) {
      Object effectiveError = error;
      // A server restart can leave an otherwise authenticated client holding
      // an obsolete JWT. Refresh once from the stored sign-in session, then
      // retry the same message only when the first response was explicitly
      // unauthorized. Network failures must never be retried as sends here.
      if (_canRecoverSupportAuth(effectiveError)) {
        _lastSupportAuthRecovery = DateTime.now();
        try {
          await ref
              .read(authControllerProvider.notifier)
              .setForegroundPresence(true);
          final refreshed = ref.read(authControllerProvider).session;
          if (refreshed == null || refreshed.sessionToken.isEmpty) {
            throw const FormatException('support_session_refresh_failed');
          }
          await _api.create(refreshed, current.id);
          String attachmentId = '';
          if (draft.kind != SupportMessageKind.text) {
            attachmentId = await _api.upload(refreshed, File(draft.value));
          }
          final sent = await _api.send(refreshed, current.id, draft,
              attachmentId: attachmentId);
          _replaceMessage(draft.id, sent);
          return;
        } catch (retryError) {
          effectiveError = retryError;
        }
      }
      // The server can persist a message immediately before a proxy closes the
      // response. Re-read history once so a successful write is never shown as
      // a permanent client-side failure.
      // Allow the reconciliation request to run before showing a failure.
      // _syncRemote intentionally skips work while a send is active.
      if (mounted) setState(() => _sending = false);
      await _syncRemote(force: true);
      // A reverse proxy can close the response after the server has already
      // persisted the message. In that case reconciliation replaced the draft
      // with its authoritative remote copy; never overwrite it as failed.
      final reconciled = _active?.messages.any((message) =>
              message.id != draft.id &&
              message.kind == draft.kind &&
              message.mine == draft.mine &&
              (message.kind == SupportMessageKind.text
                  ? message.value == draft.value
                  : (message.createdAt - draft.createdAt).abs() < 30000)) ??
          false;
      if (reconciled) return;
      if (_active?.messages.any((message) => message.id == draft.id) ?? false) {
        _replaceMessage(
            draft.id,
            SupportMessage(
              id: draft.id,
              createdAt: draft.createdAt,
              kind: draft.kind,
              value: draft.value,
              durationMs: draft.durationMs,
              attachmentId: draft.attachmentId,
              failed: true,
            ));
      }
      if (mounted) _showSendError(effectiveError);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /* void _showSendError([Object? error]) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(error == null
                ? '消息未发送，请检查网络后重试。'
                : '消息未发送：${error.toString().replaceFirst('FormatException: ', '')}')),
      ); */

  void _showSendError([Object? error]) {
    final raw = error?.toString().replaceFirst('FormatException: ', '') ?? '';
    final detail = raw == 'account_muted'
        ? 'Messaging is temporarily restricted for this account.'
        : raw == 'invalid_attachment'
            ? 'The media upload could not be verified. Choose it again.'
            : raw == 'upload_too_large'
                ? 'This media file is too large to send.'
                : raw.startsWith('support_network:')
                    ? 'Unable to reach the message service. Please retry.'
                    : raw.isEmpty
                        ? 'Message was not sent. Please try again.'
                        : 'Message was not sent: $raw';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(detail)));
  }

  SupportMessage _newMessage(SupportMessageKind kind, String value,
      {int durationMs = 0}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return SupportMessage(
      id: '$now-${kind.name}',
      createdAt: now,
      kind: kind,
      value: value,
      durationMs: durationMs,
    );
  }

  Future<void> _pickMedia() async {
    final selected = await FilePicker.platform.pickFiles(
      type: FileType.media,
      allowMultiple: false,
    );
    if (!mounted || selected == null || selected.files.isEmpty) return;
    final file = selected.files.single;
    final source = file.path;
    if (source == null) return;
    final ext = file.extension?.toLowerCase() ?? '';
    final kind = const {'mp4', 'mkv', 'mov', 'webm', '3gp'}.contains(ext)
        ? SupportMessageKind.video
        : SupportMessageKind.image;
    final directory = await getApplicationSupportDirectory();
    final mediaDirectory = Directory('${directory.path}/support-media');
    await mediaDirectory.create(recursive: true);
    final local = File(
        '${mediaDirectory.path}/${DateTime.now().millisecondsSinceEpoch}.$ext');
    await File(source).copy(local.path);
    if (!mounted) return;
    await _sendMessage(_newMessage(kind, local.path));
  }

  Future<void> _captureMedia() async {
    if (!mounted) return;
    final video = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: Text(context.l10n.chatTakePhoto),
            onTap: () => Navigator.pop(context, false),
          ),
          ListTile(
            leading: const Icon(Icons.videocam_outlined),
            title: Text(context.l10n.chatRecordVideo),
            onTap: () => Navigator.pop(context, true),
          ),
        ]),
      ),
    );
    if (video == null) return;
    final picker = ImagePicker();
    final picked = video
        ? await picker.pickVideo(
            source: ImageSource.camera,
            maxDuration: const Duration(seconds: 15),
          )
        : await picker.pickImage(source: ImageSource.camera, imageQuality: 92);
    if (picked == null) return;
    await _copyAndSendMedia(
      picked.path,
      video ? SupportMessageKind.video : SupportMessageKind.image,
    );
  }

  Future<void> _chooseMediaSource() async {
    if (!mounted) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.camera_alt_outlined),
            title: Text(context.l10n.chatCaptureMedia),
            onTap: () => Navigator.pop(context, 'camera'),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(context.l10n.chatChooseMedia),
            onTap: () => Navigator.pop(context, 'library'),
          ),
        ]),
      ),
    );
    if (action == 'camera') {
      await _captureMedia();
    } else if (action == 'library') {
      await _pickMedia();
    }
  }

  Future<void> _copyAndSendMedia(String source, SupportMessageKind kind) async {
    final extension = source.split('.').last.toLowerCase();
    final directory = await getApplicationSupportDirectory();
    final mediaDirectory = Directory('${directory.path}/support-media');
    await mediaDirectory.create(recursive: true);
    final local = File(
        '${mediaDirectory.path}/${DateTime.now().millisecondsSinceEpoch}.$extension');
    await File(source).copy(local.path);
    if (!mounted) return;
    await _sendMessage(_newMessage(kind, local.path));
  }

  Future<void> _startVoice(LongPressStartDetails _) async {
    final started = await VoiceRecorderChannel.start();
    if (!mounted || !started) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_text(context, 'microphonePermission'))),
        );
      }
      return;
    }
    setState(() {
      _recording = true;
      _cancelVoice = false;
      _voiceDragDistance = 0;
      _voiceStartedAt = DateTime.now();
    });
  }

  void _updateVoice(LongPressMoveUpdateDetails details) {
    if (!_recording) return;
    _voiceDragDistance = details.offsetFromOrigin.dy;
    final cancel = _voiceDragDistance < -42;
    if (cancel != _cancelVoice) setState(() => _cancelVoice = cancel);
  }

  Future<void> _finishVoice(LongPressEndDetails _) async {
    if (!_recording) return;
    final cancelled = _cancelVoice;
    final startedAt = _voiceStartedAt;
    setState(() {
      _recording = false;
      _cancelVoice = false;
      _voiceDragDistance = 0;
      _voiceStartedAt = null;
    });
    if (cancelled) {
      await VoiceRecorderChannel.cancel();
      return;
    }
    final path = await VoiceRecorderChannel.stop();
    if (!mounted || path == null) return;
    final durationMs = startedAt == null
        ? 0
        : DateTime.now().difference(startedAt).inMilliseconds;
    await _sendMessage(
        _newMessage(SupportMessageKind.voice, path, durationMs: durationMs));
  }

  Future<void> _cancelActiveVoice() async {
    if (!_recording) return;
    setState(() {
      _recording = false;
      _cancelVoice = false;
      _voiceDragDistance = 0;
      _voiceStartedAt = null;
    });
    await VoiceRecorderChannel.cancel();
  }

  Future<void> _openMedia(SupportMessage message) async {
    var path = message.value;
    if (!File(path).existsSync() && message.attachmentId.isNotEmpty) {
      final session = ref.read(authControllerProvider).session;
      if (session == null) return;
      try {
        final cache = await getTemporaryDirectory();
        path = (await _api.download(
          session,
          message.attachmentId,
          message.value,
          cache,
        ))
            .path;
      } catch (_) {
        if (mounted) _showSendError();
        return;
      }
    }
    if (message.kind == SupportMessageKind.image && File(path).existsSync()) {
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _ImagePreviewScreen(path: path),
      ));
      return;
    }
    if (message.kind == SupportMessageKind.video && File(path).existsSync()) {
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _VideoPreviewScreen(path: path),
      ));
      return;
    }
    if (message.kind == SupportMessageKind.voice) {
      await VoiceRecorderChannel.playVoice(path);
    } else {
      await VoiceRecorderChannel.openMedia(path);
    }
  }

  Future<void> _recall(SupportMessage message) async {
    if (!message.mine || message.failed) {
      _replaceMessage(message.id, null);
      return;
    }
    final session = ref.read(authControllerProvider).session;
    final conversationId = _activeConversationId;
    if (session == null || conversationId == null) return;
    try {
      await _api.recall(session, conversationId, message.id);
      _replaceMessage(message.id, null);
    } catch (_) {
      if (mounted) _showSendError(const FormatException('support_recall'));
    }
  }

  Future<void> _messageActions(SupportMessage message) async {
    if (!message.mine) return;
    final recall = await showModalBottomSheet<bool>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListTile(
          leading: const Icon(Icons.undo_rounded),
          title:
              Text(message.failed ? 'Remove failed message' : 'Recall message'),
          onTap: () => Navigator.pop(sheetContext, true),
        ),
      ),
    );
    if (recall == true) await _recall(message);
  }

  void _newConversation() {
    Navigator.of(context).pop();
    _activeConversationId = null;
    _ensureActiveConversation();
  }

  Future<void> _deleteConversation(SupportConversation conversation) async {
    final session = ref.read(authControllerProvider).session;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除历史对话'),
        content: const Text('这会删除该对话的全部消息和媒体附件，且无法恢复。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (confirmed != true || session == null) return;
    try {
      await _api.deleteConversation(session, conversation.id);
      if (!mounted) return;
      setState(() {
        _conversations.removeWhere((item) => item.id == conversation.id);
        if (_activeConversationId == conversation.id) {
          _activeConversationId = _conversations.firstOrNull?.id;
        }
      });
      await _persist();
      _ensureActiveConversation();
    } catch (error) {
      if (mounted) _showSendError(error);
    }
  }

  void _selectConversation(String id) {
    setState(() => _activeConversationId = id);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.edit_square),
                title: Text(_text(context, 'newConversation')),
                onTap: _newConversation,
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(_text(context, 'previousConversations')),
                ),
              ),
              Expanded(
                child: _conversations.isEmpty
                    ? Center(child: Text(_text(context, 'noConversations')))
                    : ListView.builder(
                        itemCount: _conversations.length,
                        itemBuilder: (context, index) {
                          final item = _conversations[index];
                          return ListTile(
                            selected: item.id == _activeConversationId,
                            leading: const Icon(Icons.chat_bubble_outline),
                            trailing: IconButton(
                              tooltip: '删除对话',
                              icon: const Icon(Icons.delete_outline_rounded),
                              onPressed: () => _deleteConversation(item),
                            ),
                            title: Text(item.title,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                                _messageCount(context, item.messages.length)),
                            onTap: () => _selectConversation(item.id),
                            onLongPress: () => _deleteConversation(item),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
      appBar: AppBar(
        leading: Builder(
          builder: (context) => IconButton(
            tooltip: _text(context, 'conversations'),
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_text(context, 'supportTitle')),
            Text(_text(context, 'supportSubtitle'),
                style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Stack(children: [
              Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        const _TextBubble(
                          text:
                              'Hello. Describe the issue and include the steps that led to it. Astraeus will review your report.',
                          mine: false,
                        ),
                        for (final message in _messages)
                          _MessageBubble(
                            message: message,
                            onOpen: () => _openMedia(message),
                            onLongPress: () => _messageActions(message),
                          ),
                      ],
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            height: 56,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(28),
                              boxShadow: const [
                                BoxShadow(
                                    color: Color(0x22000000),
                                    blurRadius: 12,
                                    offset: Offset(0, 3))
                              ],
                            ),
                            child: Row(children: [
                              IconButton(
                                tooltip: _text(context, 'photoOrVideo'),
                                onPressed: _chooseMediaSource,
                                color: Colors.black87,
                                icon: const Icon(Icons.camera_alt_outlined),
                              ),
                              Expanded(
                                child: _voiceMode
                                    ? GestureDetector(
                                        onLongPressStart: _startVoice,
                                        onLongPressMoveUpdate: _updateVoice,
                                        onLongPressEnd: _finishVoice,
                                        onLongPressCancel: _cancelActiveVoice,
                                        child: Container(
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                              color: _recording
                                                  ? const Color(0xffe8eef7)
                                                  : Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(20)),
                                          child: Text(
                                              _recording
                                                  ? (_cancelVoice
                                                      ? 'Release to cancel'
                                                      : 'Release to send')
                                                  : 'Hold to talk',
                                              style: const TextStyle(
                                                  color: Colors.black87,
                                                  fontWeight: FontWeight.w600)),
                                        ),
                                      )
                                    : TextField(
                                        controller: _message,
                                        onChanged: (value) {
                                          _typingChanged(value);
                                          setState(() {});
                                        },
                                        onSubmitted: (_) => _send(),
                                        minLines: 1,
                                        maxLines: 2,
                                        decoration: InputDecoration(
                                            hintText:
                                                context.l10n.chatMessageHint,
                                            border: InputBorder.none,
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 12)),
                                      ),
                              ),
                              if (_voiceMode || _message.text.trim().isEmpty)
                                IconButton(
                                  tooltip:
                                      _voiceMode ? 'Text input' : 'Voice input',
                                  onPressed: () =>
                                      setState(() => _voiceMode = !_voiceMode),
                                  color: Colors.black87,
                                  icon: Icon(_voiceMode
                                      ? Icons.keyboard_rounded
                                      : Icons.mic_none_rounded),
                                ),
                              if (!_voiceMode)
                                Tooltip(
                                  message: _text(context, 'send'),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 180),
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: !_voiceMode &&
                                              _message.text.trim().isNotEmpty
                                          ? const Color(0xff1677ff)
                                          : const Color(0xffeef1f4),
                                      boxShadow: !_voiceMode &&
                                              _message.text.trim().isNotEmpty
                                          ? const [
                                              BoxShadow(
                                                  color: Color(0x331677FF),
                                                  blurRadius: 10,
                                                  offset: Offset(0, 3))
                                            ]
                                          : null,
                                    ),
                                    child: IconButton(
                                      visualDensity: VisualDensity.compact,
                                      onPressed: !_voiceMode &&
                                              _message.text.trim().isNotEmpty &&
                                              !_sending
                                          ? _send
                                          : null,
                                      icon: const Icon(
                                          Icons.arrow_upward_rounded),
                                      color: Colors.white,
                                      disabledColor: const Color(0xff9aa4ae),
                                    ),
                                  ),
                                ),
                            ]),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (_recording)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _VoiceRecordingOverlay(
                    cancelling: _cancelVoice,
                    onCancel: _cancelActiveVoice,
                  ),
                ),
            ]),
    );
  }
}

class _VoiceRecordingOverlay extends StatefulWidget {
  const _VoiceRecordingOverlay(
      {required this.cancelling, required this.onCancel});

  final bool cancelling;
  final Future<void> Function() onCancel;

  @override
  State<_VoiceRecordingOverlay> createState() => _VoiceRecordingOverlayState();
}

class _VoiceRecordingOverlayState extends State<_VoiceRecordingOverlay> {
  Timer? _amplitudeTimer;
  bool _samplingAmplitude = false;
  double _level = 0;

  @override
  void initState() {
    super.initState();
    _amplitudeTimer = Timer.periodic(
        const Duration(milliseconds: 100), (_) => _sampleAmplitude());
  }

  Future<void> _sampleAmplitude() async {
    if (_samplingAmplitude) return;
    _samplingAmplitude = true;
    try {
      final raw = await VoiceRecorderChannel.amplitude();
      if (!mounted) return;

      // MediaRecorder exposes the actual peak level. One in-flight request and
      // a small dead-band keep the panel responsive without needless rebuilds.
      final next = (raw / 15000).clamp(0.0, 1.0);
      final smoothed = _level * .58 + next * .42;
      if ((smoothed - _level).abs() >= .01) {
        setState(() => _level = smoothed);
      }
    } finally {
      _samplingAmplitude = false;
    }
  }

  @override
  void dispose() {
    _amplitudeTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cancelling = widget.cancelling;
    final panelColor =
        cancelling ? const Color(0xffad3d43) : const Color(0xff0f6397);
    return ClipPath(
      clipper: const _VoiceArcClipper(),
      child: Material(
        color: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        child: Container(
          height: 202,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: cancelling
                  ? const [Color(0xffc84d52), Color(0xff8d2933)]
                  : const [Color(0xff1979ae), Color(0xff08446e)],
            ),
            boxShadow: [
              BoxShadow(
                  color: panelColor.withValues(alpha: .28),
                  blurRadius: 22,
                  spreadRadius: 2,
                  offset: const Offset(0, -4))
            ],
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                const SizedBox(height: 66),
                Text(
                  cancelling
                      ? 'Release to cancel'
                      : 'Release to send, slide up to cancel',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 14),
                RepaintBoundary(
                  child: SizedBox(
                    height: 52,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: List.generate(31, (index) {
                          final distance = (index - 15).abs() / 15;
                          final arch =
                              (1 - distance * distance).clamp(0.0, 1.0);
                          final height = 4 + arch * (8 + _level * 31);
                          return Container(
                            width: 2,
                            height: height,
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(
                              color: Colors.white
                                  .withValues(alpha: .72 + arch * .28),
                              borderRadius: BorderRadius.circular(99),
                            ),
                          );
                        }),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A real arch across the panel's top edge: the centre rises above both sides,
/// like the curved edge of a protractor rather than a rounded rectangle.
class _VoiceArcClipper extends CustomClipper<Path> {
  const _VoiceArcClipper();

  @override
  Path getClip(Size size) {
    final path = Path()..moveTo(0, 66);
    path.quadraticBezierTo(size.width / 2, -2, size.width, 66);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant _VoiceArcClipper oldClipper) => false;
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble(
      {required this.message, required this.onOpen, required this.onLongPress});
  final SupportMessage message;
  final VoidCallback onOpen;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return switch (message.kind) {
      SupportMessageKind.text => GestureDetector(
          onLongPress: onLongPress,
          child: _TextBubble(
              text: message.value, mine: message.mine, failed: message.failed)),
      SupportMessageKind.image => _MediaBubble(
          message: message,
          icon: Icons.image_outlined,
          onOpen: onOpen,
          onLongPress: onLongPress),
      SupportMessageKind.video => _MediaBubble(
          message: message,
          icon: Icons.play_circle_outline,
          onOpen: onOpen,
          onLongPress: onLongPress),
      SupportMessageKind.voice => _MediaBubble(
          message: message,
          icon: Icons.play_arrow_rounded,
          onOpen: onOpen,
          onLongPress: onLongPress),
    };
  }
}

class _TextBubble extends StatelessWidget {
  const _TextBubble(
      {required this.text, required this.mine, this.failed = false});
  final String text;
  final bool mine;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final color = mine ? Theme.of(context).colorScheme.primary : Colors.white;
    final onColor =
        mine ? Theme.of(context).colorScheme.onPrimary : Colors.black87;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
            color: color, borderRadius: BorderRadius.circular(16)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(child: Text(text, style: TextStyle(color: onColor))),
          if (failed)
            Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Icon(Icons.error_outline, size: 16, color: onColor)),
        ]),
      ),
    );
  }
}

class _MediaBubble extends StatefulWidget {
  const _MediaBubble(
      {required this.message,
      required this.icon,
      required this.onOpen,
      required this.onLongPress});
  final SupportMessage message;
  final IconData icon;
  final VoidCallback onOpen;
  final VoidCallback onLongPress;

  @override
  State<_MediaBubble> createState() => _MediaBubbleState();
}

class _MediaBubbleState extends State<_MediaBubble> {
  double _voiceSpeed = 1;

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final isImage = message.kind == SupportMessageKind.image;
    final isVoice = message.kind == SupportMessageKind.voice;
    final theme = Theme.of(context);
    if (isVoice) {
      final seconds = ((message.durationMs / 1000).ceil()).clamp(1, 3600);
      return Align(
        alignment: message.mine ? Alignment.centerRight : Alignment.centerLeft,
        child: InkWell(
          onTap: () =>
              VoiceRecorderChannel.playVoice(message.value, speed: _voiceSpeed),
          onLongPress: widget.onLongPress,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            width: (132 + seconds.clamp(0, 30) * 2).toDouble(),
            constraints: const BoxConstraints(maxWidth: 210),
            height: 44,
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: message.mine
                  ? theme.colorScheme.primary
                  : theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(children: [
              Icon(Icons.play_arrow_rounded,
                  size: 24,
                  color: message.mine
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onSurface),
              const SizedBox(width: 7),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(
                    9,
                    (index) => Container(
                      width: 2,
                      height: 6.0 + ((index * 7) % 11),
                      color: (message.mine
                              ? theme.colorScheme.onPrimary
                              : theme.colorScheme.onSurface)
                          .withValues(alpha: .72),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text('$seconds"',
                  style: TextStyle(
                      fontSize: 12,
                      color: message.mine
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurfaceVariant)),
              TextButton(
                onPressed: () => setState(() => _voiceSpeed = _voiceSpeed == 1
                    ? 1.5
                    : _voiceSpeed == 1.5
                        ? 2
                        : 1),
                style: TextButton.styleFrom(
                    minimumSize: const Size(34, 34), padding: EdgeInsets.zero),
                child: Text('${_voiceSpeed}x',
                    style: TextStyle(
                        fontSize: 11,
                        color: message.mine
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.primary)),
              ),
            ]),
          ),
        ),
      );
    }
    return Align(
      alignment: message.mine ? Alignment.centerRight : Alignment.centerLeft,
      child: InkWell(
        onTap: widget.onOpen,
        onLongPress: widget.onLongPress,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 220,
          margin: const EdgeInsets.only(bottom: 10),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(16)),
          child: isImage && File(message.value).existsSync()
              ? Image.file(File(message.value), height: 160, fit: BoxFit.cover)
              : message.kind == SupportMessageKind.video
                  ? AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Stack(fit: StackFit.expand, children: [
                        Container(color: Colors.black87),
                        const Center(
                            child: Icon(Icons.play_circle_fill_rounded,
                                color: Colors.white, size: 52)),
                        Positioned(
                            left: 10,
                            right: 10,
                            bottom: 8,
                            child: Text(
                                File(message.value).uri.pathSegments.last,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white))),
                      ]))
                  : message.mediaLoading
                      ? const SizedBox(
                          height: 160,
                          child: Center(
                            child: SizedBox(
                              width: 28,
                              height: 28,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        )
                      : Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Icon(widget.icon, size: 30),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  message.kind == SupportMessageKind.voice
                                      ? 'Voice message · ${((message.durationMs / 1000).ceil()).clamp(1, 3600)}s'
                                      : File(message.value)
                                          .uri
                                          .pathSegments
                                          .last,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
        ),
      ),
    );
  }
}

class _ImagePreviewScreen extends StatelessWidget {
  const _ImagePreviewScreen({required this.path});
  final String path;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: InteractiveViewer(
            minScale: 0.8,
            maxScale: 5,
            child: Image.file(File(path), fit: BoxFit.contain),
          ),
        ),
      );
}

class _VideoPreviewScreen extends StatefulWidget {
  const _VideoPreviewScreen({required this.path});
  final String path;

  @override
  State<_VideoPreviewScreen> createState() => _VideoPreviewScreenState();
}

class _VideoPreviewScreenState extends State<_VideoPreviewScreen> {
  late final VideoPlayerController _controller;
  late final Future<void> _ready;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.path));
    _ready = _controller.initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
            backgroundColor: Colors.black, foregroundColor: Colors.white),
        body: Center(
          child: FutureBuilder<void>(
            future: _ready,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const CircularProgressIndicator(color: Colors.white);
              }
              if (snapshot.hasError) {
                return Text(context.l10n.chatVideoPreviewUnavailable,
                    style: TextStyle(color: Colors.white));
              }
              return GestureDetector(
                onTap: () => setState(() => _controller.value.isPlaying
                    ? _controller.pause()
                    : _controller.play()),
                child: AspectRatio(
                  aspectRatio: _controller.value.aspectRatio,
                  child: Stack(alignment: Alignment.center, children: [
                    VideoPlayer(_controller),
                    if (!_controller.value.isPlaying)
                      const Icon(Icons.play_circle_fill_rounded,
                          color: Colors.white, size: 64),
                    Positioned(
                        left: 16,
                        right: 16,
                        bottom: 10,
                        child: VideoProgressIndicator(_controller,
                            allowScrubbing: true,
                            colors: const VideoProgressColors(
                                playedColor: Colors.lightBlueAccent))),
                  ]),
                ),
              );
            },
          ),
        ),
      );
}

String _text(BuildContext context, String key) {
  final language = Localizations.localeOf(context).languageCode;
  const values = <String, Map<String, String>>{
    'en': {
      'microphonePermission': 'Allow microphone access, then hold to record.',
      'newConversation': 'New conversation',
      'previousConversations': 'Previous conversations',
      'noConversations': 'No previous conversations',
      'conversations': 'Conversations',
      'supportTitle': 'Astraeus Support',
      'supportSubtitle': 'Astraeus is here to help',
      'photoOrVideo': 'Photo or video',
      'messageAstraeus': 'Message Astraeus',
      'send': 'Send',
    },
    'zh': {
      'microphonePermission': '请允许麦克风权限，然后长按录音。',
      'newConversation': '新建对话',
      'previousConversations': '历史对话',
      'noConversations': '暂无历史对话',
      'conversations': '对话',
      'supportTitle': 'Astraeus 客服',
      'supportSubtitle': 'Astraeus 将为您提供帮助',
      'photoOrVideo': '图片或视频',
      'messageAstraeus': '发送消息给 Astraeus',
      'send': '发送',
    },
    'es': {
      'microphonePermission':
          'Permite el acceso al micrófono y mantén pulsado para grabar.',
      'newConversation': 'Nueva conversación',
      'previousConversations': 'Conversaciones anteriores',
      'noConversations': 'No hay conversaciones anteriores',
      'conversations': 'Conversaciones',
      'supportTitle': 'Soporte de Astraeus',
      'supportSubtitle': 'Astraeus está aquí para ayudarte',
      'photoOrVideo': 'Foto o vídeo',
      'messageAstraeus': 'Mensaje para Astraeus',
      'send': 'Enviar',
    },
    'ja': {
      'microphonePermission': 'マイクへのアクセスを許可してから、長押しして録音してください。',
      'newConversation': '新しい会話',
      'previousConversations': '過去の会話',
      'noConversations': '過去の会話はありません',
      'conversations': '会話',
      'supportTitle': 'Astraeus サポート',
      'supportSubtitle': 'Astraeus がお手伝いします',
      'photoOrVideo': '写真または動画',
      'messageAstraeus': 'Astraeus にメッセージ',
      'send': '送信',
    },
  };
  final isTraditional = Localizations.localeOf(context).scriptCode == 'Hant';
  if (language == 'zh' && isTraditional) {
    const traditional = <String, String>{
      'microphonePermission': '請允許麥克風權限，然後長按錄音。',
      'newConversation': '新增對話',
      'previousConversations': '歷史對話',
      'noConversations': '暫無歷史對話',
      'conversations': '對話',
      'supportTitle': 'Astraeus 客服',
      'supportSubtitle': 'Astraeus 將為您提供協助',
      'photoOrVideo': '圖片或影片',
      'messageAstraeus': '傳送訊息給 Astraeus',
      'send': '傳送',
    };
    return traditional[key] ?? values['en']![key]!;
  }
  return values[language]?[key] ?? values['en']![key]!;
}

String _messageCount(BuildContext context, int count) {
  switch (Localizations.localeOf(context).languageCode) {
    case 'zh':
      return '$count 条消息';
    case 'es':
      return '$count mensajes';
    case 'ja':
      return '$count 件のメッセージ';
    default:
      return '$count messages';
  }
}
