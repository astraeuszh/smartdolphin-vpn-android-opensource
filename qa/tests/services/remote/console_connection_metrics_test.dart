import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smartdolphin_vpn/services/remote/console_connection_metrics.dart';

void main() {
  test('readiness probe accepts the first valid tunnel exit IP', () async {
    final service = ConsoleConnectionMetrics(
      client: MockClient((request) async {
        if (request.url.host == 'api64.ipify.org') {
          return http.Response('{"ip":"23.27.134.86"}', 200);
        }
        return http.Response('upstream unavailable', 503);
      }),
    );

    final result = await service.probe(timeout: const Duration(seconds: 1));

    expect(result.ip, '23.27.134.86');
    expect(result.isIpv4, isTrue);
    expect(result.probeMs, greaterThanOrEqualTo(0));
  });

  test('readiness probe rejects malformed responses', () async {
    final service = ConsoleConnectionMetrics(
      client: MockClient((_) async => http.Response('not-an-ip', 200)),
    );

    expect(
      service.probe(timeout: const Duration(seconds: 1)),
      throwsA(isA<StateError>()),
    );
  });

  test('production-style probes do not reuse pre-tunnel sockets', () async {
    var clientsCreated = 0;
    final service = ConsoleConnectionMetrics(
      probeClientFactory: () {
        clientsCreated++;
        final ip = clientsCreated == 1 ? '192.0.2.10' : '23.27.134.86';
        return MockClient((request) async {
          if (request.url.host == 'api64.ipify.org') {
            return http.Response('{"ip":"$ip"}', 200);
          }
          return http.Response('upstream unavailable', 503);
        });
      },
    );

    final before = await service.probe(timeout: const Duration(seconds: 1));
    final after = await service.probe(timeout: const Duration(seconds: 1));

    expect(before.ip, '192.0.2.10');
    expect(after.ip, '23.27.134.86');
    expect(clientsCreated, 2);
  });
}
