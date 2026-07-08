import 'dart:io';

Future<Set<String>> resolveDomainToIpv4(String domain) async {
  final ips = <String>{};
  try {
    final addresses = await InternetAddress.lookup(domain);
    for (final a in addresses) {
      if (a.type == InternetAddressType.IPv4) {
        ips.add(a.address);
      }
    }
  } catch (_) {
    // Caller may log
  }
  return ips;
}
