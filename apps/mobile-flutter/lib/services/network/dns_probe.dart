import 'dart:async';
import 'dart:io';

/// 校验 IPv4 并探测 DNS 端口是否可达。
class DnsProbe {
  static bool isValidIpv4(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    for (final part in parts) {
      if (part.isEmpty || part.length > 3) return false;
      final n = int.tryParse(part);
      if (n == null || n < 0 || n > 255) return false;
    }
    return true;
  }

  static bool isValidPublicResolverIpv4(String ip) {
    if (!isValidIpv4(ip)) return false;
    final parts = ip.split('.').map(int.parse).toList(growable: false);
    final a = parts[0];
    final b = parts[1];
    final c = parts[2];
    final d = parts[3];

    if (a == 0 || a == 10 || a == 127 || a >= 224) return false;
    if (a == 100 && b >= 64 && b <= 127) return false;
    if (a == 169 && b == 254) return false;
    if (a == 172 && b >= 16 && b <= 31) return false;
    if (a == 192 && b == 168) return false;
    if (a == 192 && b == 0 && c == 0) return false;
    if (a == 198 && (b == 18 || b == 19)) return false;
    if (a == 255 && b == 255 && c == 255 && d == 255) return false;
    return true;
  }

  static Future<bool> checkReachable(String ip,
      {Duration timeout = const Duration(seconds: 4)}) async {
    if (!isValidPublicResolverIpv4(ip)) return false;
    try {
      final socket = await Socket.connect(ip, 53, timeout: timeout);
      await socket.close();
      return true;
    } catch (_) {
      return false;
    }
  }
}
