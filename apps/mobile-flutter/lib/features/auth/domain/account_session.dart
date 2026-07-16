import 'traffic_policy.dart';

import 'account_datetime.dart';

class AccountSession {
  const AccountSession({
    required this.username,
    required this.password,
    required this.uid,
    this.publicUid = '',
    required this.expireAt,
    required this.sessionToken,
    required this.deviceId,
    this.banned = false,
    this.locked = false,
    this.banReason = '',
    this.permissionLevel = 0,
    this.trafficPolicy = const TrafficPolicy(),
    this.email = '',
    this.createdAt = 0,
    this.subscribedAt = 0,
    this.mutedUntil = 0,
    this.notificationId = 0,
    this.notificationType = '',
    this.notificationTitle = '',
    this.notificationBody = '',
  });

  final String username;
  final String password;
  final int uid;
  final String publicUid;
  final int expireAt;
  final String sessionToken;
  final String deviceId;
  final bool banned;
  final bool locked;
  final String banReason;
  final int permissionLevel;
  final TrafficPolicy trafficPolicy;
  final String email;
  final int createdAt;
  final int subscribedAt;
  final int mutedUntil;
  final int notificationId;
  final String notificationType;
  final String notificationTitle;
  final String notificationBody;

  bool get isMuted =>
      mutedUntil > DateTime.now().millisecondsSinceEpoch ~/ 1000;

  bool get isPending => expireAt <= 0 && !banned;

  bool get isExpired {
    if (expireAt <= 0 || expireAt >= kPermanentExpireUnix) {
      return false;
    }
    return DateTime.now().millisecondsSinceEpoch ~/ 1000 >= expireAt;
  }

  bool get expiresWithinOneDay {
    if (isTrial || expireAt <= 0 || expireAt >= kPermanentExpireUnix) {
      return false;
    }
    final remaining = expireAt - DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return remaining > 0 && remaining <= const Duration(days: 1).inSeconds;
  }

  /// True while the account is still within the initial 1-day self-registration trial.
  bool get isTrial {
    if (expireAt <= 0) return false;
    if (expireAt >= kPermanentExpireUnix) return false;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (now >= expireAt) return false;
    if (createdAt <= 0) {
      return expireAt <= now + kTrialDurationSec + 120;
    }
    return expireAt <= createdAt + kTrialDurationSec + 120;
  }

  bool get canUseVpn {
    if (banned || locked) return false;
    if (trafficPolicy.isAccountLocked) return false;
    if (trafficPolicy.overQuota) return false;
    if (expireAt <= 0) return sessionToken.isNotEmpty;
    if (expireAt >= kPermanentExpireUnix) return true;
    return !isExpired;
  }

  factory AccountSession.fromJson({
    required String username,
    required String password,
    required String deviceId,
    required Map<String, dynamic> data,
  }) {
    final expire = _asInt(data['expire_at'] ?? data['expire_time']);
    final uid =
        _asInt(data['id'] ?? data['sub'] ?? data['internal_id'] ?? data['uid']);
    final publicUid = '${data['uid'] ?? data['public_uid'] ?? ''}';
    final token =
        (data['session_token'] as String?) ?? (data['token'] as String?) ?? '';
    return AccountSession(
      username: username,
      password: password,
      uid: uid,
      publicUid: publicUid,
      expireAt: expire,
      sessionToken: token,
      deviceId: (data['device_id'] as String?)?.isNotEmpty == true
          ? data['device_id'] as String
          : deviceId,
      banned: data['banned'] == true,
      locked: data['locked'] == true,
      banReason: '${data['ban_reason'] ?? ''}',
      permissionLevel: _asInt(data['permission_level']),
      trafficPolicy: TrafficPolicy.fromJson(data),
      email: (data['email'] as String?) ?? '',
      createdAt: _asInt(data['created_at']),
      subscribedAt: _asInt(data['subscribed_at']),
      mutedUntil: _asInt(data['muted_until']),
      notificationId: _asInt((data['notification'] as Map?)?['id']),
      notificationType: '${(data['notification'] as Map?)?['type'] ?? ''}',
      notificationTitle: '${(data['notification'] as Map?)?['title'] ?? ''}',
      notificationBody: '${(data['notification'] as Map?)?['body'] ?? ''}',
    );
  }

  AccountSession copyWithRemote(Map<String, dynamic> data) {
    final expire = _asInt(data['expire_at'] ?? data['expire_time']);
    final token = (data['session_token'] as String?) ??
        (data['token'] as String?) ??
        sessionToken;
    return AccountSession(
      username: username,
      password: password,
      uid: uid > 0 ? uid : _asInt(data['uid'] ?? data['id'] ?? data['sub']),
      publicUid: '${data['uid'] ?? data['public_uid'] ?? publicUid}',
      expireAt: expire > 0 ? expire : expireAt,
      sessionToken: token.isNotEmpty ? token : sessionToken,
      deviceId: deviceId,
      banned: data.containsKey('banned') ? data['banned'] == true : banned,
      locked: data.containsKey('locked') ? data['locked'] == true : locked,
      banReason: data.containsKey('ban_reason')
          ? '${data['ban_reason'] ?? ''}'
          : banReason,
      permissionLevel: _asInt(data['permission_level']),
      trafficPolicy: trafficPolicy.mergeFrom(data),
      email: (data['email'] as String?)?.isNotEmpty == true
          ? data['email'] as String
          : email,
      createdAt: _asInt(data['created_at']) > 0
          ? _asInt(data['created_at'])
          : createdAt,
      subscribedAt: _asInt(data['subscribed_at']) > 0
          ? _asInt(data['subscribed_at'])
          : subscribedAt,
      mutedUntil: data.containsKey('muted_until')
          ? _asInt(data['muted_until'])
          : mutedUntil,
      notificationId: _asInt((data['notification'] as Map?)?['id']),
      notificationType: '${(data['notification'] as Map?)?['type'] ?? ''}',
      notificationTitle: '${(data['notification'] as Map?)?['title'] ?? ''}',
      notificationBody: '${(data['notification'] as Map?)?['body'] ?? ''}',
    );
  }

  Map<String, dynamic> toJson() => {
        'username': username,
        'password': password,
        'uid': uid,
        'public_uid': publicUid,
        'expire_at': expireAt,
        'session_token': sessionToken,
        'device_id': deviceId,
        'banned': banned,
        'locked': locked,
        'ban_reason': banReason,
        'permission_level': permissionLevel,
        'email': email,
        'created_at': createdAt,
        'subscribed_at': subscribedAt,
        'muted_until': mutedUntil,
        'notification': notificationId > 0
            ? {
                'id': notificationId,
                'type': notificationType,
                'title': notificationTitle,
                'body': notificationBody,
              }
            : null,
        ...trafficPolicy.toJson(),
      };

  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }
}
