import 'traffic_policy.dart';

class AccountSession {
  const AccountSession({
    required this.username,
    required this.password,
    required this.uid,
    required this.expireAt,
    required this.sessionToken,
    required this.deviceId,
    this.banned = false,
    this.permissionLevel = 0,
    this.trafficPolicy = const TrafficPolicy(),
    this.email = '',
  });

  final String username;
  final String password;
  final int uid;
  final int expireAt;
  final String sessionToken;
  final String deviceId;
  final bool banned;
  final int permissionLevel;
  final TrafficPolicy trafficPolicy;
  final String email;

  bool get isPending => expireAt <= 0 && !banned;

  bool get canUseVpn {
    if (banned || expireAt <= 0) return false;
    if (expireAt >= 4000000000) return true;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return now <= expireAt;
  }

  factory AccountSession.fromJson({
    required String username,
    required String password,
    required String deviceId,
    required Map<String, dynamic> data,
  }) {
    final expire = _asInt(data['expire_at'] ?? data['expire_time']);
    return AccountSession(
      username: username,
      password: password,
      uid: _asInt(data['uid']),
      expireAt: expire,
      sessionToken: (data['session_token'] as String?) ?? '',
      deviceId: (data['device_id'] as String?)?.isNotEmpty == true
          ? data['device_id'] as String
          : deviceId,
      banned: data['banned'] == true,
      permissionLevel: _asInt(data['permission_level']),
      trafficPolicy: TrafficPolicy.fromJson(data),
      email: (data['email'] as String?) ?? '',
    );
  }

  AccountSession copyWithRemote(Map<String, dynamic> data) {
    final expire = _asInt(data['expire_at'] ?? data['expire_time']);
    return AccountSession(
      username: username,
      password: password,
      uid: uid > 0 ? uid : _asInt(data['uid']),
      expireAt: expire > 0 ? expire : expireAt,
      sessionToken: (data['session_token'] as String?)?.isNotEmpty == true
          ? data['session_token'] as String
          : sessionToken,
      deviceId: deviceId,
      banned: data['banned'] == true,
      permissionLevel: _asInt(data['permission_level']),
      trafficPolicy: TrafficPolicy.fromJson(data),
      email: (data['email'] as String?)?.isNotEmpty == true
          ? data['email'] as String
          : email,
    );
  }

  Map<String, dynamic> toJson() => {
        'username': username,
        'password': password,
        'uid': uid,
        'expire_at': expireAt,
        'session_token': sessionToken,
        'device_id': deviceId,
        'banned': banned,
        'permission_level': permissionLevel,
        'email': email,
      };

  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }
}
