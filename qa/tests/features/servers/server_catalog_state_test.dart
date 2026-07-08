import 'package:flutter_test/flutter_test.dart';

import 'package:smartdolphin_vpn/features/servers/data/country_card.dart';
import 'package:smartdolphin_vpn/features/servers/domain/server.dart';
import 'package:smartdolphin_vpn/features/servers/domain/server_catalog_controller.dart';

void main() {
  test('sortedCountryCards prioritizes pinned (HK, US) then connectable by latency', () {
    const us = Server(
      id: 'smartdolphin-us',
      name: 'US',
      countryCode: 'US',
      publicKey: 'key',
      endpoint: '1.1.1.1:51820',
      allowedIps: '0.0.0.0/0',
    );
    const de = Server(
      id: 'b',
      name: 'DE',
      countryCode: 'DE',
      publicKey: 'key',
      endpoint: '2.2.2.2:51820',
      allowedIps: '0.0.0.0/0',
    );
    const in_ = Server(
      id: 'c',
      name: 'IN',
      countryCode: 'IN',
      publicKey: 'key',
      endpoint: '3.3.3.3:51820',
      allowedIps: '0.0.0.0/0',
    );
    final cards = [
      CountryCard(countryCode: 'HK', countryName: '香港', server: null, isPinned: true),
      CountryCard(countryCode: 'US', countryName: '美国', server: us, latencyMs: 50, isPinned: true),
      CountryCard(countryCode: 'DE', countryName: '德国', server: de, latencyMs: 70, isPinned: false),
      CountryCard(countryCode: 'IN', countryName: '印度', server: in_, latencyMs: 9999, isPinned: false),
    ];
    final state = ServerCatalogState(
      countryCards: cards,
      latencyMs: {'smartdolphin-us': 50, 'b': 70, 'c': 9999},
    );
    final sorted = state.sortedCountryCards;
    expect(sorted.first.countryCode, 'HK');
    expect(sorted[1].countryCode, 'US');
    expect(sorted[2].countryCode, 'DE');
    expect(sorted[3].countryCode, 'IN');
    expect(state.connectableServers.map((s) => s.id), ['smartdolphin-us', 'b']);
  });
}
