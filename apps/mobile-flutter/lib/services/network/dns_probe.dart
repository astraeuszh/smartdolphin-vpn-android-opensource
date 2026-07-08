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

  static Future<bool> checkReachable(String ip, {Duration timeout = const Duration(seconds: 4)}) async {
    if (!isValidIpv4(ip)) return false;
    try {
      final socket = await Socket.connect(ip, 53, timeout: timeout);
      await socket.close();
      return true;
    } catch (_) {
      return false;
    }
  }
}
