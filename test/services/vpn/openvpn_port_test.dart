import 'package:flutter_test/flutter_test.dart';

import 'package:smartdolphin_vpn/services/vpn/openvpn_port.dart';

void main() {
  group('OpenVPN config sanitizer', () {
    test('preserves certificate blocks and extracts credentials', () async {
      final sampleConfig = '''
client
dev tun
proto tcp
remote 1.2.3.4 443
auth-user-pass
<auth-user-pass>
vpnuser
vpnpass
</auth-user-pass>
<ca>
-----BEGIN CERTIFICATE-----
MIIBszCCAVugAwIBAgIBADAKBggqhkjOPQQDAjASMRAwDgYDVQQDDAdUZXN0Q0Ew
HhcNMjQwMTAxMDAwMDAwWhcNMzQwMTAxMDAwMDAwWjASMRAwDgYDVQQDDAdUZXN0
Q0EwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAARJj8nXrVEU5t9XX0bUQxHDc36T
DpDBT4J6sF9Cvt2Q9i7/z7S4I65EHhOArb0gIkS7AwEHoCk3xs4lBu7QptijUzBR
MB0GA1UdDgQWBBSBf6OAYoDkTxUxDcIsVYJYWG4KQTAfBgNVHSMEGDAWgBSBf6OA
YoDkTxUxDcIsVYJYWG4KQTAPBgNVHRMBAf8EBTADAQH/MAoGCCqGSM49BAMCA0gA
MEUCICUOlO1kFdTXYgWkiS1Z6j1v6Rj12p7Sg0KVIoXeCGOjAiEA3vd7NEANXzEF
4k74kV3uRJmUQ5vJv3VYZJdVhjq2O9A=
-----END CERTIFICATE-----
</ca>
''';

      final sanitizer = OpenVpnPort();
      final result = await sanitizer.debugSanitizeOpenVpnConfig(sampleConfig);

      expect(result.username, equals('vpnuser'));
      expect(result.password, equals('vpnpass'));

      final normalizedConfig = result.config;
      expect(
        RegExp(r'^auth-user-pass$', multiLine: true).allMatches(normalizedConfig).length,
        equals(1),
      );
      expect(normalizedConfig.contains('<ca>'), isTrue);
      expect(normalizedConfig.contains('</ca>'), isTrue);

      final lines = normalizedConfig.split('\n');
      final authIndex = lines.indexOf('auth-user-pass');
      expect(authIndex, isNonNegative);
      expect(lines[authIndex + 1], equals('<ca>'));
    });

    test('adds auth-user-pass directive when missing', () async {
      final sampleConfig = '''
client
remote 5.6.7.8 1194
<ca>
CA DATA
</ca>
''';

      final sanitizer = OpenVpnPort();
      final result = await sanitizer.debugSanitizeOpenVpnConfig(sampleConfig);

      expect(result.username, isNull);
      expect(result.password, isNull);

      final normalizedConfig = result.config;
      final matches =
          RegExp(r'^auth-user-pass$', multiLine: true).allMatches(normalizedConfig).length;
      expect(matches, equals(1));
      expect(normalizedConfig.contains('auth-user-pass'), isTrue);
    });

    test('injects dhcp-option DNS when setDnsServers is called', () async {
      final sampleConfig = '''
client
remote 5.6.7.8 1194
<ca>
CA DATA
</ca>
''';

      final sanitizer = OpenVpnPort();
      sanitizer.setDnsServers(const ['1.1.1.1', '1.0.0.1']);
      final result = await sanitizer.debugSanitizeOpenVpnConfig(sampleConfig);

      expect(result.config.contains('dhcp-option DNS 1.1.1.1'), isTrue);
      expect(result.config.contains('dhcp-option DNS 1.0.0.1'), isTrue);
    });

    test('removes existing dhcp-option DNS and injects custom', () async {
      final sampleConfig = '''
client
remote 5.6.7.8 1194
dhcp-option DNS 8.8.8.8
<ca>
CA DATA
</ca>
''';

      final sanitizer = OpenVpnPort();
      sanitizer.setDnsServers(const ['1.1.1.1']);
      final result = await sanitizer.debugSanitizeOpenVpnConfig(sampleConfig);

      expect(result.config.contains('dhcp-option DNS 8.8.8.8'), isFalse);
      expect(result.config.contains('dhcp-option DNS 1.1.1.1'), isTrue);
    });
  });
}
