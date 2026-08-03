import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../../../platform/android/voice_recorder_channel.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/storage/prefs.dart';
import '../../../services/remote/support_chat_api.dart';
import '../../auth/domain/account_session.dart';
import '../../auth/domain/auth_controller.dart';
import '../data/support_chat_repository.dart';
import '../domain/support_chat_models.dart';
import 'account_settings_screen.dart';
import '../../../widgets/frosted_glass.dart';

class SupportChatScreen extends ConsumerStatefulWidget {
  const SupportChatScreen({super.key});

  @override
  ConsumerState<SupportChatScreen> createState() => _SupportChatScreenState();
}

class _SupportChatScreenState extends ConsumerState<SupportChatScreen>
    with WidgetsBindingObserver {
  final _message = TextEditingController();
  final _inputFocus = FocusNode();
  final _chatScroll = ScrollController();
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
  bool _followLatest = true;
  bool _showScrollToLatest = false;
  bool _typingActive = false;
  bool _typingRequestInFlight = false;
  Timer? _typingTimer;
  StreamSubscription<void>? _messageEventSubscription;
  ProviderSubscription<AuthState>? _authSubscription;
  int _authEpoch = 0;
  final Map<String, String> _pendingAttachments = {};
  final Set<String> _remoteConversationIds = {};
  bool _syncing = false;
  bool _sidebarOpen = false;
  bool _attachmentTrayOpen = false;
  DateTime? _lastSupportAuthRecovery;
  final _api = SupportChatApi();
  static const int _messageWindowSize = 150;

  List<SupportMessage> get _messages => _active?.messages ?? const [];
  SupportConversation? get _active => _conversations
      .where((conversation) => conversation.id == _activeConversationId)
      .firstOrNull;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _chatScroll.addListener(_onChatScroll);
    _inputFocus.addListener(_onInputFocusChanged);
    _authSubscription = ref.listenManual<AuthState>(
      authControllerProvider,
      (previous, next) {
        final oldIdentity = previous?.session == null
            ? null
            : SupportChatRepository.accountKeyFor(previous!.session!);
        final newIdentity = next.session == null
            ? null
            : SupportChatRepository.accountKeyFor(next.session!);
        if (next.session == null ||
            (oldIdentity != null && newIdentity != oldIdentity)) {
          _handleSessionInvalidated();
        }
      },
    );
    _restore();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _typingTimer?.cancel();
    _messageEventSubscription?.cancel();
    _authSubscription?.close();
    _message.dispose();
    _inputFocus.dispose();
    _chatScroll.removeListener(_onChatScroll);
    _chatScroll.dispose();
    super.dispose();
  }

  void _onInputFocusChanged() {
    if (mounted) setState(() {});
  }

  void _onChatScroll() {
    if (!_chatScroll.hasClients) return;
    final follow =
        _chatScroll.position.maxScrollExtent - _chatScroll.offset < 72;
    if (follow != _followLatest && mounted) {
      setState(() {
        _followLatest = follow;
        _showScrollToLatest = !follow;
      });
    }
  }

  void _scrollToLatest({bool instant = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_chatScroll.hasClients) return;
      final target = _chatScroll.position.maxScrollExtent;
      if (instant) {
        _chatScroll.jumpTo(target);
      } else {
        _chatScroll.animateTo(target,
            duration: const Duration(milliseconds: 230),
            curve: Curves.easeOutCubic);
      }
      if (mounted) {
        setState(() {
          _followLatest = true;
          _showScrollToLatest = false;
        });
      }
    });
  }

  void _handleSessionInvalidated() {
    _authEpoch++;
    _typingTimer?.cancel();
    _messageEventSubscription?.cancel();
    _messageEventSubscription = null;
    _typingActive = false;
    _syncing = false;
    _sending = false;
    _repository = null;
    _pendingAttachments.clear();
    _remoteConversationIds.clear();
    if (!mounted) return;
    setState(() {
      _conversations.clear();
      _activeConversationId = null;
      _loading = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_syncRemote());
      final session = ref.read(authControllerProvider).session;
      if (session != null) _startMessageEvents(session);
    } else {
      _messageEventSubscription?.cancel();
      _messageEventSubscription = null;
    }
  }

  void _startMessageEvents(AccountSession session) {
    _messageEventSubscription?.cancel();
    _messageEventSubscription = _api.events(session).listen(
      (_) {
        if (_isPageActive) unawaited(_syncRemote(force: true));
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
    final epoch = _authEpoch;
    final accountKey = SupportChatRepository.accountKeyFor(session);
    final repository = SupportChatRepository.forSession(
      await PrefsStore.create(),
      session,
    );
    final restored = await repository.load();
    final conversations = <SupportConversation>[];
    for (var index = 0; index < restored.length; index++) {
      final conversation = restored[index];
      final messages = conversation.messages
          .skip((conversation.messages.length - _messageWindowSize)
              .clamp(0, conversation.messages.length))
          .toList(growable: false);
      conversations.add(SupportConversation(
        id: conversation.id,
        createdAt: conversation.createdAt,
        updatedAt: conversation.updatedAt,
        messageCount: conversation.messageCount,
        customTitle: conversation.customTitle.trim().isNotEmpty
            ? conversation.customTitle
            : conversation.title,
        messages: messages,
      ));
    }
    final current = ref.read(authControllerProvider).session;
    if (!mounted ||
        epoch != _authEpoch ||
        current == null ||
        SupportChatRepository.accountKeyFor(current) != accountKey) {
      return;
    }
    setState(() {
      _repository = repository;
      _conversations.addAll(conversations);
      _activeConversationId =
          conversations.isEmpty ? null : conversations.first.id;
      _loading = false;
    });
    // Render the account-scoped cache first. Network reconciliation must not
    // block the first frame or make a previously synced conversation blink.
    unawaited(_syncRemote(force: true));
    if (!mounted) return;
    _ensureActiveConversation();
    if (WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      _startMessageEvents(session);
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
    final snapshots = _conversations.map((conversation) {
      final messages = conversation.messages
          .skip((conversation.messages.length - _messageWindowSize)
              .clamp(0, conversation.messages.length))
          .toList(growable: false);
      return SupportConversation(
        id: conversation.id,
        createdAt: conversation.createdAt,
        updatedAt: conversation.updatedAt,
        messageCount: conversation.messageCount,
        customTitle: conversation.customTitle.trim().isNotEmpty
            ? conversation.customTitle
            : conversation.title,
        messages: messages,
      );
    }).toList(growable: false);
    await repository.save(snapshots);
  }

  void _append(SupportMessage message) {
    final current = _active;
    if (current == null) return;
    final updated = SupportConversation(
      id: current.id,
      createdAt: current.createdAt,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      messageCount: current.messages.length + 1,
      customTitle: current.customTitle,
      messages: [...current.messages, message],
    );
    setState(() {
      final index = _conversations.indexWhere((item) => item.id == current.id);
      _conversations[index] = updated;
    });
    _scrollToLatest();
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
      customTitle: current.customTitle,
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
    final epoch = _authEpoch;
    final accountKey = SupportChatRepository.accountKeyFor(session);
    _syncing = true;
    try {
      final remote = await _api.conversations(session);
      if (!_isCurrentSupportSession(epoch, accountKey)) return;
      final remoteIds = remote.map((item) => item.id).toSet();
      _remoteConversationIds
        ..clear()
        ..addAll(remoteIds);
      // The server list is authoritative. Only failed local drafts are kept;
      // conversations removed with an account/server-side deletion must not
      // remain visible forever from SharedPreferences.
      final unresolvedLocalDrafts = _conversations
          .where((item) =>
              !remoteIds.contains(item.id) &&
              (item.messages.any((message) => message.failed) ||
                  (item.id == _activeConversationId && item.messages.isEmpty)))
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
        final reconcileActive = conversation.id == _activeConversationId;
        if (!reconcileActive) {
          final summary = SupportConversation(
            id: conversation.id,
            createdAt: conversation.createdAt,
            updatedAt: conversation.updatedAt,
            messageCount: conversation.messageCount,
            customTitle: conversation.customTitle.trim().isNotEmpty
                ? conversation.customTitle
                : (cached?.title ?? ''),
            messages: cached?.messages ?? const [],
          );
          if (localIndex < 0) {
            _conversations.add(summary);
          } else {
            _conversations[localIndex] = summary;
          }
          continue;
        }
        if (!changed && cached.messages.isNotEmpty && !force) {
          continue;
        }
        final remoteMessages = await _api.messages(session, conversation.id);
        if (!_isCurrentSupportSession(epoch, accountKey)) return;
        final messages = <SupportMessage>[];
        final windowStart = (remoteMessages.length - _messageWindowSize)
            .clamp(0, remoteMessages.length);
        for (final message in remoteMessages.skip(windowStart)) {
          final local = localIndex < 0
              ? const <SupportMessage>[]
              : _conversations[localIndex].messages;
          messages.add(await _mergeRemoteMessage(session, local, message));
          if (!_isCurrentSupportSession(epoch, accountKey)) return;
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
          customTitle: conversation.customTitle,
          messages: [...messages, ...unresolved],
        );
        if (index < 0) {
          _conversations.add(hydrated);
        } else {
          _conversations[index] = hydrated;
        }
      }
      _conversations.addAll(unresolvedLocalDrafts);
      _conversations.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (!_conversations.any((item) => item.id == _activeConversationId)) {
        _activeConversationId = _conversations.firstOrNull?.id;
      }
      if (mounted) {
        setState(() {});
        if (_followLatest) {
          _scrollToLatest(instant: force);
        } else {
          _showScrollToLatest = true;
        }
      }
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

  bool _isCurrentSupportSession(int epoch, String accountKey) {
    if (!mounted || epoch != _authEpoch) return false;
    final current = ref.read(authControllerProvider).session;
    return current != null &&
        SupportChatRepository.accountKeyFor(current) == accountKey;
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
    if (remote.attachmentId.isNotEmpty && _repository != null) {
      final cache = await _repository!.mediaCacheDirectory();
      final prefix = '${remote.attachmentId}-';
      final matches = cache
          .listSync()
          .whereType<File>()
          .where((file) => file.uri.pathSegments.last.startsWith(prefix))
          .toList();
      if (matches.isNotEmpty) {
        return SupportMessage(
          id: remote.id,
          createdAt: remote.createdAt,
          kind: remote.kind,
          value: matches.first.path,
          mine: remote.mine,
          durationMs: remote.durationMs,
          attachmentId: remote.attachmentId,
        );
      }
    }
    // Remote media is downloaded only when the user opens or saves it. Eager
    // downloads on every poll retained large buffers/files and made an idle
    // support screen consume several times the expected memory and power.
    return remote;
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
      await _ensureRemoteConversation(session, current.id);
      String attachmentId = _pendingAttachments[draft.id] ?? '';
      if (draft.kind != SupportMessageKind.text && attachmentId.isEmpty) {
        attachmentId = await _api.upload(session, File(draft.value));
        _pendingAttachments[draft.id] = attachmentId;
      }
      final sent = await _api.send(session, current.id, draft,
          attachmentId: attachmentId);
      _pendingAttachments.remove(draft.id);
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
          await _ensureRemoteConversation(refreshed, current.id);
          String attachmentId = _pendingAttachments[draft.id] ?? '';
          if (draft.kind != SupportMessageKind.text && attachmentId.isEmpty) {
            attachmentId = await _api.upload(refreshed, File(draft.value));
            _pendingAttachments[draft.id] = attachmentId;
          }
          final sent = await _api.send(refreshed, current.id, draft,
              attachmentId: attachmentId);
          _pendingAttachments.remove(draft.id);
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

  Future<void> _ensureRemoteConversation(
      AccountSession session, String conversationId) async {
    if (_remoteConversationIds.contains(conversationId)) return;
    await _api.create(session, conversationId);
    _remoteConversationIds.add(conversationId);
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
        ? _text(context, 'accountMuted')
        : raw == 'invalid_attachment'
            ? _text(context, 'invalidAttachment')
            : raw == 'upload_too_large'
                ? _text(context, 'uploadTooLarge')
                : raw.startsWith('support_network:')
                    ? _text(context, 'messageNetworkError')
                    : raw.isEmpty
                        ? _text(context, 'messageNotSent')
                        : '${_text(context, 'messageNotSent')} $raw';
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

  Future<void> _chooseImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: Text(context.l10n.chatTakePhoto),
            onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(_text(context, 'choosePhoto')),
            onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
          ),
        ]),
      ),
    );
    if (source == null) return;
    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 92,
    );
    if (picked != null) {
      await _copyAndSendMedia(picked.path, SupportMessageKind.image);
    }
  }

  Future<void> _chooseVideo() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.videocam_outlined),
            title: Text(context.l10n.chatRecordVideo),
            onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.video_library_outlined),
            title: Text(_text(context, 'chooseVideo')),
            onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
          ),
        ]),
      ),
    );
    if (source == null) return;
    final picked = await ImagePicker().pickVideo(
      source: source,
      maxDuration: const Duration(minutes: 5),
    );
    if (picked != null) {
      await _copyAndSendMedia(picked.path, SupportMessageKind.video);
    }
  }

  Future<void> _pickFile() async {
    final selected = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );
    if (!mounted || selected == null || selected.files.isEmpty) return;
    final picked = selected.files.single;
    final source = picked.path;
    if (source == null) return;
    final size = await File(source).length();
    if (size <= 0 || size > 1024 * 1024 * 1024) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_text(context, 'fileTooLarge'))),
        );
      }
      return;
    }
    final repository = _repository;
    if (repository == null) return;
    final directory = await repository.outgoingMediaDirectory();
    final safeName = picked.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final local = File(
      '${directory.path}/${DateTime.now().millisecondsSinceEpoch}-$safeName',
    );
    await File(source).copy(local.path);
    if (!mounted) return;
    await _sendMessage(_newMessage(SupportMessageKind.file, local.path));
  }

  Future<void> _copyAndSendMedia(String source, SupportMessageKind kind) async {
    final extension = source.split('.').last.toLowerCase();
    final repository = _repository;
    if (repository == null) return;
    final mediaDirectory = await repository.outgoingMediaDirectory();
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
    final repository = _repository;
    if (repository == null) return;
    final directory = await repository.outgoingMediaDirectory();
    final extension = path.split('.').last.toLowerCase();
    final local = File(
        '${directory.path}/${DateTime.now().millisecondsSinceEpoch}.$extension');
    await File(path).copy(local.path);
    try {
      await File(path).delete();
    } catch (_) {
      // The private cache directory is disposable; failure must not block send.
    }
    if (!mounted) return;
    await _sendMessage(_newMessage(SupportMessageKind.voice, local.path,
        durationMs: durationMs));
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
        final cache = await _repository?.mediaCacheDirectory();
        if (cache == null) return;
        final existing = cache
            .listSync()
            .whereType<File>()
            .where((file) => file.uri.pathSegments.last.startsWith(
                  '${message.attachmentId}-',
                ))
            .firstOrNull;
        path = existing?.path ??
            (await _api.download(
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
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.kind == SupportMessageKind.text)
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: Text(_text(context, 'copyText')),
                onTap: () => Navigator.pop(sheetContext, 'copy'),
              ),
            if (message.kind != SupportMessageKind.text)
              ListTile(
                leading: const Icon(Icons.download_rounded),
                title: Text(_text(context, 'download')),
                onTap: () => Navigator.pop(sheetContext, 'download'),
              ),
            if (message.mine)
              ListTile(
                leading: const Icon(Icons.undo_rounded),
                title: Text(message.failed
                    ? _text(context, 'removeFailedMessage')
                    : _text(context, 'recallMessage')),
                onTap: () => Navigator.pop(sheetContext, 'recall'),
              ),
          ],
        ),
      ),
    );
    if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: message.value));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_text(context, 'copied'))),
        );
      }
    } else if (action == 'download') {
      await _downloadMessage(message);
    } else if (action == 'recall') {
      await _recall(message);
    }
  }

  Future<void> _downloadMessage(SupportMessage message) async {
    var path = message.value;
    final fileName = File(path).uri.pathSegments.lastOrNull ??
        (message.value.trim().isEmpty
            ? _text(context, 'attachment')
            : message.value.trim());
    if (!File(path).existsSync()) {
      final session = ref.read(authControllerProvider).session;
      final repository = _repository;
      if (session == null ||
          repository == null ||
          message.attachmentId.isEmpty) {
        return;
      }
      try {
        path = (await _api.download(
          session,
          message.attachmentId,
          fileName,
          await repository.mediaCacheDirectory(),
        ))
            .path;
      } catch (_) {
        if (mounted) _showSendError(const FormatException('support_download'));
        return;
      }
    }
    final saved = await VoiceRecorderChannel.saveToDownloads(path, fileName);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(saved == null
            ? _text(context, 'downloadFailed')
            : _text(context, 'savedToDownloads')),
      ));
    }
  }

  void _newConversation() {
    setState(() => _sidebarOpen = false);
    _activeConversationId = null;
    _ensureActiveConversation();
  }

  double _composerHeight() {
    if (_recording) return 72;
    final estimatedLines = _message.text.isEmpty
        ? 2
        : (_message.text.length / 34).ceil() +
            '\n'.allMatches(_message.text).length;
    final lines = math.max(2, math.min(8, estimatedLines));
    final availableHeight = MediaQuery.sizeOf(context).height * .72;
    return math.min(availableHeight, 48 + lines * 24).toDouble();
  }

  Future<void> _openFullScreenEditor() async {
    final controller = TextEditingController(text: _message.text);
    final value = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (screenContext) => Scaffold(
          appBar: AppBar(
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(screenContext, controller.text),
                child: Text(_text(context, 'send')),
              ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(18),
            child: TextField(
              controller: controller,
              autofocus: true,
              expands: true,
              minLines: null,
              maxLines: null,
              textAlignVertical: TextAlignVertical.top,
              decoration:
                  InputDecoration(hintText: context.l10n.chatMessageHint),
            ),
          ),
        ),
      ),
    );
    controller.dispose();
    if (value == null || !mounted) return;
    _message.text = value;
    _message.selection = TextSelection.collapsed(offset: value.length);
    _typingChanged(value);
    setState(() {});
  }

  Future<void> _deleteConversation(SupportConversation conversation) async {
    final session = ref.read(authControllerProvider).session;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_text(context, 'deleteConversation')),
        content: Text(_text(context, 'deleteConversationBody')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(_text(context, 'cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(_text(context, 'delete'))),
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

  Future<void> _renameConversation(SupportConversation conversation) async {
    final session = ref.read(authControllerProvider).session;
    if (session == null) return;
    final controller = TextEditingController(text: conversation.title);
    final title = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_text(context, 'renameConversation')),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
              hintText: _text(context, 'conversationTitleHint')),
          onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(_text(context, 'cancel')),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: Text(_text(context, 'confirm')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (title == null || title.isEmpty || title == conversation.title) return;
    final index =
        _conversations.indexWhere((item) => item.id == conversation.id);
    if (index < 0) return;
    final current = _conversations[index];
    setState(() {
      _conversations[index] = SupportConversation(
        id: current.id,
        createdAt: current.createdAt,
        updatedAt: current.updatedAt,
        messageCount: current.messageCount,
        messages: current.messages,
        customTitle: title,
      );
    });
    await _persist();
    // Title sync is best effort so a client can still rename local history
    // during a rolling server deployment. The account-scoped repository keeps
    // the title stable on this device and a later rename will sync it again.
    try {
      await _ensureRemoteConversation(session, conversation.id);
      await _api.renameConversation(session, conversation.id, title);
    } catch (_) {}
  }

  Future<void> _conversationActions(SupportConversation conversation) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(_text(context, 'renameConversation')),
              onTap: () => Navigator.pop(sheetContext, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded,
                  color: Colors.redAccent),
              title: Text(_text(context, 'delete'),
                  style: const TextStyle(color: Colors.redAccent)),
              onTap: () => Navigator.pop(sheetContext, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (action == 'rename') {
      await _renameConversation(conversation);
    } else if (action == 'delete') {
      await _deleteConversation(conversation);
    }
  }

  void _selectConversation(String id) {
    if (id == _activeConversationId) {
      setState(() => _sidebarOpen = false);
      return;
    }
    setState(() {
      final previous = _activeConversationId;
      _activeConversationId = id;
      if (previous != null) {
        final index = _conversations.indexWhere((item) => item.id == previous);
        if (index >= 0) {
          final item = _conversations[index];
          _conversations[index] = SupportConversation(
            id: item.id,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt,
            messageCount: item.messageCount,
            customTitle: item.customTitle.trim().isNotEmpty
                ? item.customTitle
                : item.title,
            messages: const [],
          );
        }
      }
    });
    setState(() => _sidebarOpen = false);
    unawaited(_syncRemote(force: true));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: dark ? const Color(0xFF181C20) : const Color(0xFFF3F4F5),
      body: LayoutBuilder(builder: (context, constraints) {
        final sidebarWidth = constraints.maxWidth * .78;
        final stageColor =
            dark ? const Color(0xFF181C20) : const Color(0xFFF8F9FB);
        final panelColor = dark
            ? const Color(0xF02B3035)
            : Colors.white.withValues(alpha: .94);
        return Stack(children: [
          SizedBox(
            width: sidebarWidth,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 14, 14),
                child: Column(children: [
                  Row(children: [
                    CircleAvatar(
                      backgroundColor: dark
                          ? const Color(0xFF3A3F44)
                          : const Color(0xFFE3E5E7),
                      child: Text('A',
                          style: TextStyle(
                              color: theme.colorScheme.onSurface,
                              fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('Astraeus',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                    ),
                    Tooltip(
                      message: _text(context, 'newConversation'),
                      child: Material(
                        color: Colors.transparent,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _newConversation,
                          child: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: dark
                                  ? const Color(0xFF30353A)
                                  : Colors.white.withValues(alpha: .76),
                              border: Border.all(
                                  color: Colors.white
                                      .withValues(alpha: dark ? .12 : .92)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: .12),
                                  blurRadius: 14,
                                  offset: const Offset(0, 5),
                                ),
                              ],
                            ),
                            child: const Stack(
                              alignment: Alignment.center,
                              children: [
                                Icon(Icons.chat_bubble_outline_rounded,
                                    size: 23),
                                Positioned(
                                  right: 9,
                                  bottom: 9,
                                  child:
                                      Icon(Icons.add_circle_rounded, size: 14),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 18),
                  _SidebarAction(title: '唤醒客服', onTap: () {}),
                  _SidebarAction(title: '自动上报', onTap: () {}),
                  const SizedBox(height: 16),
                  Row(children: [
                    Text(_text(context, 'previousConversations'),
                        style: theme.textTheme.labelLarge),
                    const SizedBox(width: 10),
                    const Expanded(child: Divider()),
                  ]),
                  const SizedBox(height: 8),
                  Expanded(
                    child: _conversations.isEmpty
                        ? Center(child: Text(_text(context, 'noConversations')))
                        : ListView.builder(
                            itemCount: _conversations.length,
                            itemBuilder: (context, index) {
                              final item = _conversations[index];
                              final selected = item.id == _activeConversationId;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: ListTile(
                                  selected: selected,
                                  selectedTileColor: theme.colorScheme.primary
                                      .withValues(alpha: dark ? .18 : .10),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14)),
                                  title: Text(item.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          color: theme.colorScheme.onSurface,
                                          fontWeight: FontWeight.w600)),
                                  onTap: () => _selectConversation(item.id),
                                  onLongPress: () => _conversationActions(item),
                                ),
                              );
                            },
                          ),
                  ),
                ]),
              ),
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 520),
            curve: const Cubic(.32, .72, 0, 1),
            transformAlignment: Alignment.centerLeft,
            transform: _sidebarOpen
                ? (Matrix4.identity()
                  ..setEntry(0, 0, .96)
                  ..setEntry(1, 1, .96)
                  ..setTranslationRaw(sidebarWidth * 1.04, 0, 0))
                : Matrix4.identity(),
            decoration: BoxDecoration(
              color: stageColor,
              borderRadius: BorderRadius.circular(_sidebarOpen ? 28 : 0),
              boxShadow: _sidebarOpen
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: .28),
                        blurRadius: 36,
                        offset: const Offset(-8, 10),
                      )
                    ]
                  : null,
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(children: [
              Column(children: [
                SafeArea(
                  bottom: false,
                  child: SizedBox(
                    height: 58,
                    child: Row(children: [
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: _text(context, 'conversations'),
                        onPressed: () {
                          _inputFocus.unfocus();
                          setState(() {
                            _attachmentTrayOpen = false;
                            _sidebarOpen = true;
                          });
                        },
                        icon: const Icon(Icons.menu_rounded),
                      ),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => Navigator.of(context).push<void>(
                                MaterialPageRoute<void>(
                                  builder: (_) => const AccountSettingsScreen(),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                child: Text('Astraeus',
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(
                                            fontWeight: FontWeight.w600)),
                              ),
                            ),
                            Text(_text(context, 'supportSubtitle'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 56),
                    ]),
                  ),
                ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : ListView.builder(
                          controller: _chatScroll,
                          padding: EdgeInsets.fromLTRB(
                              20, 12, 20, _attachmentTrayOpen ? 282 : 122),
                          itemCount: _messages.length + 1,
                          itemBuilder: (context, index) {
                            if (index == 0) {
                              return const _TextBubble(
                                text:
                                    'Hello. Describe the issue and include the steps that led to it. Astraeus will review your report.',
                                mine: false,
                              );
                            }
                            final message = _messages[index - 1];
                            return _MessageBubble(
                              key: ValueKey(message.id),
                              message: message,
                              onOpen: () => _openMedia(message),
                              onLongPress: () => _messageActions(message),
                            );
                          },
                        ),
                ),
              ]),
              if (_sidebarOpen)
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () => setState(() => _sidebarOpen = false),
                  ),
                ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 0,
                child: SafeArea(
                  top: false,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 320),
                    curve: const Cubic(.32, .72, 0, 1),
                    height: _attachmentTrayOpen ? 220 : _composerHeight(),
                    padding: _attachmentTrayOpen
                        ? const EdgeInsets.fromLTRB(20, 22, 20, 12)
                        : const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: _attachmentTrayOpen
                          ? panelColor
                          : (_recording
                              ? (_cancelVoice
                                  ? const Color(0xFFFF4D4F)
                                  : theme.colorScheme.primary)
                              : Colors.white),
                      borderRadius: _attachmentTrayOpen
                          ? const BorderRadius.vertical(
                              top: Radius.circular(24),
                            )
                          : BorderRadius.circular(9999),
                      border: Border.all(
                        color: _attachmentTrayOpen || _recording
                            ? Colors.transparent
                            : const Color(0xFFE8E8ED),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                              alpha: _attachmentTrayOpen ? .10 : .06),
                          blurRadius: _attachmentTrayOpen ? 28 : 14,
                          offset: Offset(0, _attachmentTrayOpen ? -4 : 5),
                          spreadRadius: _attachmentTrayOpen ? -6 : -3,
                        )
                      ],
                    ),
                    child: _attachmentTrayOpen
                        ? Column(children: [
                            Row(children: [
                              IconButton(
                                tooltip: _text(context, 'closeAttachments'),
                                onPressed: () =>
                                    setState(() => _attachmentTrayOpen = false),
                                icon: const Icon(Icons.close_rounded),
                              ),
                              const Spacer(),
                              Text(_text(context, 'sendAttachment'),
                                  style: theme.textTheme.titleSmall),
                              const Spacer(),
                              const SizedBox(width: 48),
                            ]),
                            const SizedBox(height: 8),
                            Expanded(
                              child: Row(children: [
                                _SupportTrayButton(
                                  icon: Icons.image_outlined,
                                  label: _text(context, 'image'),
                                  onTap: () {
                                    setState(() => _attachmentTrayOpen = false);
                                    unawaited(_chooseImage());
                                  },
                                ),
                                _SupportTrayButton(
                                  icon: Icons.video_library_outlined,
                                  label: _text(context, 'video'),
                                  onTap: () {
                                    setState(() => _attachmentTrayOpen = false);
                                    unawaited(_chooseVideo());
                                  },
                                ),
                                _SupportTrayButton(
                                  icon: Icons.folder_open_outlined,
                                  label: _text(context, 'file'),
                                  onTap: () {
                                    setState(() => _attachmentTrayOpen = false);
                                    unawaited(_pickFile());
                                  },
                                ),
                              ]),
                            ),
                          ])
                        : Row(children: [
                            if (!_recording)
                              IconButton(
                                tooltip: _text(context, 'photoVideoFile'),
                                onPressed: () {
                                  _inputFocus.unfocus();
                                  setState(() => _attachmentTrayOpen = true);
                                },
                                icon: const Icon(Icons.add_rounded),
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
                                              ? (_cancelVoice
                                                  ? theme.colorScheme.error
                                                  : theme.colorScheme.primary)
                                              : Colors.transparent,
                                          borderRadius:
                                              BorderRadius.circular(26),
                                        ),
                                        child: Text(
                                          _recording
                                              ? (_cancelVoice
                                                  ? _text(context,
                                                      'releaseToCancel')
                                                  : _text(
                                                      context, 'releaseToSend'))
                                              : _text(context, 'holdToTalk'),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: _recording
                                                ? Colors.white
                                                : theme.colorScheme.onSurface,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    )
                                  : Stack(
                                      alignment: Alignment.centerRight,
                                      children: [
                                        TextField(
                                          focusNode: _inputFocus,
                                          controller: _message,
                                          onChanged: (value) {
                                            _typingChanged(value);
                                            setState(() {});
                                          },
                                          minLines: 2,
                                          maxLines: null,
                                          decoration: InputDecoration(
                                            filled: false,
                                            hintText:
                                                context.l10n.chatMessageHint,
                                            border: InputBorder.none,
                                            enabledBorder: InputBorder.none,
                                            focusedBorder: InputBorder.none,
                                            contentPadding:
                                                const EdgeInsets.fromLTRB(
                                                    8, 10, 36, 10),
                                          ),
                                        ),
                                        if (_message.text.length > 90 ||
                                            _message.text.contains('\n'))
                                          IconButton(
                                            tooltip:
                                                _text(context, 'expandEditor'),
                                            onPressed: _openFullScreenEditor,
                                            icon: const Icon(
                                                Icons.open_in_full_rounded,
                                                size: 19),
                                          ),
                                      ],
                                    ),
                            ),
                            if (!_recording)
                              IconButton(
                                tooltip: _voiceMode
                                    ? _text(context, 'textInput')
                                    : _text(context, 'voiceInput'),
                                onPressed: () => setState(() {
                                  _voiceMode = !_voiceMode;
                                  if (!_voiceMode) _inputFocus.requestFocus();
                                }),
                                icon: Icon(_voiceMode
                                    ? Icons.keyboard_rounded
                                    : Icons.mic_none_rounded),
                              ),
                            if (!_recording &&
                                !_voiceMode &&
                                _message.text.trim().isNotEmpty)
                              IconButton.filled(
                                tooltip: _text(context, 'send'),
                                onPressed: _sending ? null : _send,
                                icon: const Icon(Icons.arrow_upward_rounded),
                              ),
                          ]),
                  ),
                ),
              ),
              if (_showScrollToLatest)
                Positioned(
                  right: 20,
                  bottom: _attachmentTrayOpen ? 236 : 74,
                  child: FloatingActionButton.small(
                    heroTag: 'support-scroll-latest',
                    tooltip: _text(context, 'jumpToLatest'),
                    onPressed: _scrollToLatest,
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black87,
                    shape: const CircleBorder(),
                    child: const Icon(Icons.keyboard_arrow_down_rounded),
                  ),
                ),
              if (_recording)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 78,
                  child: _VoiceRecordingOverlay(
                    cancelling: _cancelVoice,
                  ),
                ),
            ]),
          ),
        ]);
      }),
    );
  }
}

class _SidebarAction extends StatelessWidget {
  const _SidebarAction({required this.title, required this.onTap});
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            alignment: Alignment.centerLeft,
            foregroundColor: Theme.of(context).colorScheme.onSurface,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
          ),
          child:
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      );
}

class _SupportTrayButton extends StatelessWidget {
  const _SupportTrayButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: .11),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, color: theme.colorScheme.primary, size: 28),
            ),
            const SizedBox(height: 8),
            Text(label, style: theme.textTheme.labelMedium),
          ]),
        ),
      ),
    );
  }
}

class _VoiceRecordingOverlay extends StatefulWidget {
  const _VoiceRecordingOverlay({required this.cancelling});

  final bool cancelling;

  @override
  State<_VoiceRecordingOverlay> createState() => _VoiceRecordingOverlayState();
}

class _VoiceRecordingOverlayState extends State<_VoiceRecordingOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _waveController;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _waveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cancelling = widget.cancelling;
    final color = cancelling
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: _waveController,
      builder: (context, child) => Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(17, (index) {
          final wave = math.sin(
            _waveController.value * math.pi * 2 + index * .55,
          );
          final height = 12 + (wave + 1) * 22;
          return Container(
            width: 4,
            height: height.clamp(6, 52),
            margin: const EdgeInsets.symmetric(horizontal: 2.5),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble(
      {super.key,
      required this.message,
      required this.onOpen,
      required this.onLongPress});
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
      SupportMessageKind.file => _MediaBubble(
          message: message,
          icon: Icons.insert_drive_file_outlined,
          onOpen: onLongPress,
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
    final theme = Theme.of(context);
    final onColor =
        mine ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface;
    final radius = BorderRadius.only(
      topLeft: Radius.circular(mine ? 18 : 4),
      topRight: Radius.circular(mine ? 4 : 18),
      bottomLeft: const Radius.circular(18),
      bottomRight: const Radius.circular(18),
    );
    final content = Row(mainAxisSize: MainAxisSize.min, children: [
      Flexible(
          child: Text(text, style: TextStyle(color: onColor, height: 1.45))),
      if (failed)
        Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Icon(Icons.error_outline, size: 16, color: onColor)),
    ]);
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: mine
              ? DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        theme.colorScheme.primary.withValues(alpha: .86),
                        theme.colorScheme.primary,
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: theme.colorScheme.primary.withValues(alpha: .24),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: content,
                  ),
                )
              : FrostedGlass(
                  surface: GlassSurface.flat,
                  borderRadius: radius,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: content,
                ),
        ),
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
                                      ? '${_text(context, 'voiceMessage')} · ${((message.durationMs / 1000).ceil()).clamp(1, 3600)}s'
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
      'choosePhoto': 'Choose photo',
      'chooseVideo': 'Choose video',
      'sendAttachment': 'Send attachment',
      'image': 'Image',
      'video': 'Video',
      'file': 'File',
      'expandEditor': 'Expand editor',
      'accountMuted': 'Messaging is temporarily restricted for this account.',
      'invalidAttachment':
          'The media upload could not be verified. Choose it again.',
      'uploadTooLarge': 'This media file is too large to send.',
      'messageNetworkError':
          'Unable to reach the message service. Please retry.',
      'messageNotSent': 'Message was not sent. Please try again.',
      'fileTooLarge': 'Files must be no larger than 1 GB.',
      'copyText': 'Copy text',
      'download': 'Download',
      'removeFailedMessage': 'Remove failed message',
      'recallMessage': 'Recall message',
      'copied': 'Copied',
      'attachment': 'attachment',
      'downloadFailed': 'Download failed',
      'savedToDownloads': 'Saved to Downloads',
      'deleteConversation': 'Delete conversation',
      'deleteConversationBody':
          'All messages and media in this conversation will be deleted permanently.',
      'cancel': 'Cancel',
      'delete': 'Delete',
      'renameConversation': 'Rename conversation',
      'conversationTitleHint': 'Enter a new conversation title',
      'confirm': 'Confirm',
      'closeAttachments': 'Close attachments',
      'photoVideoFile': 'Photo, video or file',
      'releaseToCancel': 'Release to cancel',
      'releaseToSend': 'Release to send, slide up to cancel',
      'holdToTalk': 'Hold to talk',
      'textInput': 'Text input',
      'voiceInput': 'Voice input',
      'jumpToLatest': 'Jump to latest message',
      'voiceMessage': 'Voice message',
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
      'choosePhoto': '选择图片',
      'chooseVideo': '选择视频',
      'sendAttachment': '发送附件',
      'image': '图片',
      'video': '视频',
      'file': '文件',
      'expandEditor': '展开编辑器',
      'accountMuted': '此账号的消息功能暂时受限。',
      'invalidAttachment': '无法验证该媒体文件，请重新选择。',
      'uploadTooLarge': '该媒体文件过大，无法发送。',
      'messageNetworkError': '无法连接消息服务，请重试。',
      'messageNotSent': '消息未发送，请重试。',
      'fileTooLarge': '文件大小不能超过 1 GB。',
      'copyText': '复制文字',
      'download': '下载',
      'removeFailedMessage': '删除发送失败的消息',
      'recallMessage': '撤回消息',
      'copied': '已复制',
      'attachment': '附件',
      'downloadFailed': '下载失败',
      'savedToDownloads': '已保存到下载目录',
      'deleteConversation': '删除历史对话',
      'deleteConversationBody': '这会永久删除该对话的全部消息和媒体附件。',
      'cancel': '取消',
      'delete': '删除',
      'renameConversation': '更改标题名',
      'conversationTitleHint': '请输入新的对话标题',
      'confirm': '确认',
      'closeAttachments': '关闭附件栏',
      'photoVideoFile': '图片、视频或文件',
      'releaseToCancel': '松手取消',
      'releaseToSend': '松手发送，上滑取消',
      'holdToTalk': '按住说话',
      'textInput': '文字输入',
      'voiceInput': '语音输入',
      'jumpToLatest': '回到最新消息',
      'voiceMessage': '语音消息',
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
      'choosePhoto': 'Elegir foto',
      'chooseVideo': 'Elegir vídeo',
      'sendAttachment': 'Enviar archivo adjunto',
      'image': 'Imagen',
      'video': 'Vídeo',
      'file': 'Archivo',
      'expandEditor': 'Ampliar editor',
      'accountMuted':
          'La mensajería está restringida temporalmente para esta cuenta.',
      'invalidAttachment':
          'No se pudo verificar el archivo multimedia. Selecciónalo de nuevo.',
      'uploadTooLarge':
          'El archivo multimedia es demasiado grande para enviarlo.',
      'messageNetworkError':
          'No se puede conectar al servicio de mensajes. Inténtalo de nuevo.',
      'messageNotSent': 'No se envió el mensaje. Inténtalo de nuevo.',
      'fileTooLarge': 'Los archivos no pueden superar 1 GB.',
      'copyText': 'Copiar texto',
      'download': 'Descargar',
      'removeFailedMessage': 'Eliminar mensaje fallido',
      'recallMessage': 'Retirar mensaje',
      'copied': 'Copiado',
      'attachment': 'adjunto',
      'downloadFailed': 'Error de descarga',
      'savedToDownloads': 'Guardado en Descargas',
      'deleteConversation': 'Eliminar conversación',
      'deleteConversationBody':
          'Todos los mensajes y archivos de esta conversación se eliminarán permanentemente.',
      'cancel': 'Cancelar',
      'delete': 'Eliminar',
      'renameConversation': 'Cambiar título',
      'conversationTitleHint': 'Escribe un nuevo título',
      'confirm': 'Confirmar',
      'closeAttachments': 'Cerrar adjuntos',
      'photoVideoFile': 'Foto, vídeo o archivo',
      'releaseToCancel': 'Suelta para cancelar',
      'releaseToSend': 'Suelta para enviar, desliza arriba para cancelar',
      'holdToTalk': 'Mantén pulsado para hablar',
      'textInput': 'Entrada de texto',
      'voiceInput': 'Entrada de voz',
      'jumpToLatest': 'Ir al mensaje más reciente',
      'voiceMessage': 'Mensaje de voz',
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
      'choosePhoto': '写真を選択',
      'chooseVideo': '動画を選択',
      'sendAttachment': '添付ファイルを送信',
      'image': '画像',
      'video': '動画',
      'file': 'ファイル',
      'expandEditor': 'エディターを拡大',
      'accountMuted': 'このアカウントのメッセージ機能は一時的に制限されています。',
      'invalidAttachment': 'メディアを確認できませんでした。もう一度選択してください。',
      'uploadTooLarge': 'メディアファイルが大きすぎて送信できません。',
      'messageNetworkError': 'メッセージサービスに接続できません。再試行してください。',
      'messageNotSent': 'メッセージを送信できませんでした。',
      'fileTooLarge': 'ファイルは 1 GB 以下にしてください。',
      'copyText': 'テキストをコピー',
      'download': 'ダウンロード',
      'removeFailedMessage': '失敗したメッセージを削除',
      'recallMessage': 'メッセージを取り消す',
      'copied': 'コピーしました',
      'attachment': '添付ファイル',
      'downloadFailed': 'ダウンロードに失敗しました',
      'savedToDownloads': 'ダウンロードに保存しました',
      'deleteConversation': '会話を削除',
      'deleteConversationBody': 'この会話のメッセージとメディアは完全に削除されます。',
      'cancel': 'キャンセル',
      'delete': '削除',
      'renameConversation': '会話名を変更',
      'conversationTitleHint': '新しい会話名を入力',
      'confirm': '確認',
      'closeAttachments': '添付を閉じる',
      'photoVideoFile': '写真、動画、ファイル',
      'releaseToCancel': '離してキャンセル',
      'releaseToSend': '離して送信、上にスライドしてキャンセル',
      'holdToTalk': '長押しして話す',
      'textInput': 'テキスト入力',
      'voiceInput': '音声入力',
      'jumpToLatest': '最新メッセージへ',
      'voiceMessage': '音声メッセージ',
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
      'choosePhoto': '選擇圖片',
      'chooseVideo': '選擇影片',
      'sendAttachment': '傳送附件',
      'image': '圖片',
      'video': '影片',
      'file': '檔案',
      'expandEditor': '展開編輯器',
      'accountMuted': '此帳號的訊息功能暫時受限。',
      'invalidAttachment': '無法驗證該媒體檔案，請重新選擇。',
      'uploadTooLarge': '該媒體檔案過大，無法傳送。',
      'messageNetworkError': '無法連線訊息服務，請重試。',
      'messageNotSent': '訊息未傳送，請重試。',
      'fileTooLarge': '檔案大小不能超過 1 GB。',
      'copyText': '複製文字',
      'download': '下載',
      'removeFailedMessage': '刪除傳送失敗的訊息',
      'recallMessage': '收回訊息',
      'copied': '已複製',
      'attachment': '附件',
      'downloadFailed': '下載失敗',
      'savedToDownloads': '已儲存至下載目錄',
      'deleteConversation': '刪除歷史對話',
      'deleteConversationBody': '這會永久刪除該對話的全部訊息和媒體附件。',
      'cancel': '取消',
      'delete': '刪除',
      'renameConversation': '更改標題名稱',
      'conversationTitleHint': '請輸入新的對話標題',
      'confirm': '確認',
      'closeAttachments': '關閉附件列',
      'photoVideoFile': '圖片、影片或檔案',
      'releaseToCancel': '放開取消',
      'releaseToSend': '放開傳送，上滑取消',
      'holdToTalk': '按住說話',
      'textInput': '文字輸入',
      'voiceInput': '語音輸入',
      'jumpToLatest': '回到最新訊息',
      'voiceMessage': '語音訊息',
    };
    return traditional[key] ?? values['en']![key]!;
  }
  return values[language]?[key] ?? values['en']![key]!;
}
