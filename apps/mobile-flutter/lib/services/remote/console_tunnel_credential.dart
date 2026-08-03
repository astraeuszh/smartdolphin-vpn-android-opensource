import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../../features/auth/domain/account_session.dart';
import '../vpn/node_table.dart';
import 'client_request_headers.dart';

class ConsoleTunnelCredential {
  ConsoleTunnelCredential({
    http.Client? client,
    FlutterSecureStorage? storage,
  })  : _client = client ?? _sharedClient,
        _storage = storage ?? const FlutterSecureStorage();

  static const _storageKey = 'smartdolphin_tunnel_credential_v1';
  static final http.Client _sharedClient = http.Client();
  static const _bases = [
    'https://api.smartdolphinvpn.com',
    'https://smartdolphinvpn.com',
  ];

  final http.Client _client;
  final FlutterSecureStorage _storage;

  Future<SdTunnelCredential?> readyCredential(AccountSession session) async {
    final cached = await _readCached(session.uid);
    unawaited(refresh(session));
    return _isReady(cached) ? cached : null;
  }

  Future<SdTunnelCredential?> refresh(AccountSession session) async {
    if (session.sessionToken.isEmpty) return null;
    Object? lastError;
    for (final base in _bases) {
      try {
        final response = await _client
            .get(
              Uri.parse('$base/api/auth/tunnel-credential'),
              headers: await ClientRequestHeaders.standard(
                bearerToken: session.sessionToken,
              ),
            )
            .timeout(const Duration(seconds: 8));
        if (response.statusCode == 401 || response.statusCode == 403) {
          await _storage.delete(key: _storageKey);
          return null;
        }
        if (response.statusCode < 200 || response.statusCode >= 300) continue;
        final body = jsonDecode(response.body);
        if (body is! Map || body['ok'] != true) continue;
        final credentials = body['credentials'];
        if (credentials is! Map) continue;
        final credential = SdTunnelCredential(
          vlessUuid: '${credentials['vless_uuid'] ?? ''}',
          hysteriaPassword: '${credentials['hysteria_password'] ?? ''}',
          expiresAt: (body['expires_at'] as num?)?.toInt() ?? 0,
          readyAt: (body['ready_at'] as num?)?.toInt() ?? 0,
        );
        if (!_isValid(credential)) continue;
        await _storage.write(
          key: _storageKey,
          value: jsonEncode({
            'uid': session.uid,
            'vless_uuid': credential.vlessUuid,
            'hysteria_password': credential.hysteriaPassword,
            'expires_at': credential.expiresAt,
            'ready_at': credential.readyAt,
          }),
        );
        return _isReady(credential) ? credential : null;
      } on Object catch (error) {
        lastError = error;
      }
    }
    // Network failure keeps an already-issued, unexpired credential usable.
    final cached = await _readCached(session.uid);
    if (lastError != null && _isReady(cached)) return cached;
    return null;
  }

  Future<SdTunnelCredential?> _readCached(int uid) async {
    try {
      final raw = await _storage.read(key: _storageKey);
      if (raw == null || raw.isEmpty) return null;
      final body = jsonDecode(raw);
      if (body is! Map || (body['uid'] as num?)?.toInt() != uid) return null;
      final value = SdTunnelCredential(
        vlessUuid: '${body['vless_uuid'] ?? ''}',
        hysteriaPassword: '${body['hysteria_password'] ?? ''}',
        expiresAt: (body['expires_at'] as num?)?.toInt() ?? 0,
        readyAt: (body['ready_at'] as num?)?.toInt() ?? 0,
      );
      return _isValid(value) ? value : null;
    } catch (_) {
      await _storage.delete(key: _storageKey);
      return null;
    }
  }

  bool _isValid(SdTunnelCredential value) {
    return RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(value.vlessUuid) &&
        value.hysteriaPassword.length >= 16 &&
        value.hysteriaPassword.length <= 128 &&
        value.expiresAt > 0 &&
        value.readyAt > 0;
  }

  bool _isReady(SdTunnelCredential? value) {
    if (value == null) return false;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return value.readyAt <= now && value.expiresAt > now + 300;
  }
}
