import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/time.dart';
import '../../features/servers/domain/server.dart';
import '../../features/session/domain/session_state.dart';

class SessionNotificationService {
  SessionNotificationService(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;
  String? _currentServerId;
  Future<void> Function(String action)? _onAction;

  static const int _notificationId = 1337;
  static const String actionDisconnect = 'action_disconnect';

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'vpn_session_status',
    'VPN Session Status',
    description: 'Shows the current SmartDolphinVPN session status.',
    importance: Importance.max,
    showBadge: false,
    enableVibration: false,
    enableLights: false,
    playSound: false,
  );

  Future<void> initialize({Future<void> Function(String action)? onAction}) async {
    if (_initialized) {
      _onAction = onAction;
      return;
    }
    _onAction = onAction;

    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/launcher_icon'),
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        final action = response.actionId?.isNotEmpty == true
            ? response.actionId
            : response.payload;
        if (action != null && action.isNotEmpty) {
          _onAction?.call(action);
        }
      },
    );

    final androidImpl =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.createNotificationChannel(_channel);

    _initialized = true;
  }

  Future<bool> requestPermission() async {
    final androidImpl =
        _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl == null) {
      return true;
    }

    try {
      final dynamic impl = androidImpl;
      final dynamic result = await impl.requestPermission();
      if (result is bool) {
        return result;
      }
    } on NoSuchMethodError {
      // Ignore and try fallback method name.
    }

    try {
      final dynamic impl = androidImpl;
      final dynamic result = await impl.requestNotificationsPermission();
      if (result is bool) {
        return result;
      }
    } on NoSuchMethodError {
      // Ignore if the method isn't available.
    }

    return true;
  }

  Future<void> showConnecting(Server server) async {
    if (!_initialized) return;
    _currentServerId = server.id;
    final title = 'Connecting to ${_displayName(server)}';
    const body = 'Negotiating secure tunnel...';

    await _plugin.show(
      _notificationId,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          ongoing: true,
          autoCancel: false,
          onlyAlertOnce: true,
          category: AndroidNotificationCategory.service,
          priority: Priority.max,
          ticker: 'SmartDolphinVPN',
          colorized: true,
          color: Colors.blue,
          actions: const [
            AndroidNotificationAction(
              actionDisconnect,
              'Cancel',
              showsUserInterface: true,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> showConnected({
    required Server server,
    required Duration remaining,
    required SessionState state,
  }) async {
    if (!_initialized) return;
    _currentServerId = server.id;
    await _plugin.show(
      _notificationId,
      'Connected to ${_displayName(server)}',
      _buildBody(remaining: remaining, state: state),
      _details(),
      payload: actionDisconnect,
    );
  }

  Future<void> updateSession({
    required Server server,
    required Duration remaining,
    required SessionState state,
  }) async {
    if (!_initialized) return;
    if (_currentServerId != server.id) {
      await showConnected(server: server, remaining: remaining, state: state);
      return;
    }
    await _plugin.show(
      _notificationId,
      'Connected to ${_displayName(server)}',
      _buildBody(remaining: remaining, state: state),
      _details(),
      payload: actionDisconnect,
    );
  }

  Future<void> showDisconnected() async {
    if (!_initialized) return;
    await _plugin.show(
      _notificationId,
      'VPN disconnected',
      'Tap to reconnect to a secure location.',
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          autoCancel: true,
          onlyAlertOnce: true,
          category: AndroidNotificationCategory.status,
          priority: Priority.high,
        ),
      ),
    );
    _currentServerId = null;
  }

  Future<void> clear() async {
    if (!_initialized) return;
    try {
      await _plugin.cancel(_notificationId);
    } catch (e, st) {
      // ProGuard/R8 can strip TypeToken generics in release builds, causing
      // PlatformException. Swallow to avoid crashing VPN disconnect flow.
      debugPrint('[SessionNotificationService] clear failed: $e');
    }
    _currentServerId = null;
  }

  NotificationDetails _details() {
    final actions = <AndroidNotificationAction>[
      const AndroidNotificationAction(
        actionDisconnect,
        'Disconnect',
        showsUserInterface: true,
        cancelNotification: true,
      ),
    ];
    return NotificationDetails(
      android: AndroidNotificationDetails(
        _channel.id,
        _channel.name,
        channelDescription: _channel.description,
        ongoing: true,
        autoCancel: false,
        onlyAlertOnce: true,
        category: AndroidNotificationCategory.service,
        priority: Priority.max,
        colorized: true,
        color: Colors.blue,
        ticker: 'SmartDolphinVPN',
        actions: actions,
      ),
    );
  }

  String _buildBody({required Duration remaining, required SessionState state}) {
    final safeRemaining = remaining.isNegative ? Duration.zero : remaining;
    final elapsed = _elapsed(state);
    final elapsedLabel = formatNotificationDuration(elapsed);
    final remainingLabel = formatNotificationDuration(safeRemaining);
    return 'Connected: $elapsedLabel\nTime left: $remainingLabel\nDisconnect when you\'re done.';
  }

  Duration _elapsed(SessionState state) {
    final start = state.start;
    if (start == null) {
      return Duration.zero;
    }
    final now = DateTime.now().toUtc();
    final diff = now.difference(start);
    return diff.isNegative ? Duration.zero : diff;
  }

  String _displayName(Server server) {
    if (server.countryName != null && server.countryName!.isNotEmpty) {
      return server.countryName!;
    }
    return server.name;
  }
}

final sessionNotificationServiceProvider = Provider<SessionNotificationService>((ref) {
  final plugin = FlutterLocalNotificationsPlugin();
  final service = SessionNotificationService(plugin);
  ref.onDispose(() {
    service.clear();
  });
  return service;
});
