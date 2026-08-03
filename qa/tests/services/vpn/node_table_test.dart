import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartdolphin_vpn/services/vpn/node_table.dart';

void main() {
  test('Reality config uses a repository-safe placeholder public key', () {
    final config =
        jsonDecode(
              buildSingBoxConfig(
                node: kNodes.first,
                protocol: SdProtocol.reality,
              ),
            )
            as Map<String, dynamic>;
    final outbounds = config['outbounds'] as List<dynamic>;
    final reality =
        ((outbounds.first as Map<String, dynamic>)['tls']
                as Map<String, dynamic>)['reality']
            as Map<String, dynamic>;

    expect(
      reality['public_key'],
      'REPLACE_WITH_REALITY_PUBLIC_KEY',
    );
    expect(reality['short_id'], '0000000000000000');
  });

  test('WireGuard uses the endpoint schema required by the bundled core', () {
    final config =
        jsonDecode(
              buildSingBoxConfig(
                node: kNodes.first,
                protocol: SdProtocol.wireguard,
              ),
            )
            as Map<String, dynamic>;

    final endpoints = config['endpoints'] as List<dynamic>;
    expect(endpoints, hasLength(1));
    expect((endpoints.single as Map<String, dynamic>)['type'], 'wireguard');
    expect((endpoints.single as Map<String, dynamic>)['tag'], 'proxy');

    final outbounds = config['outbounds'] as List<dynamic>;
    expect(
      outbounds.where(
        (item) => (item as Map<String, dynamic>)['type'] == 'wireguard',
      ),
      isEmpty,
    );
  });
}
