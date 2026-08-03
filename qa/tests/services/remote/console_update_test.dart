import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smartdolphin_vpn/services/remote/console_update.dart';

UpdateCheckResult _release({
  required String version,
  required int build,
  bool published = true,
}) =>
    UpdateCheckResult(
      versionName: version,
      versionCode: build,
      releaseNotes: '',
      apkUrl: 'https://example.invalid/app.apk',
      forceUpdate: true,
      published: published,
      sha256: '',
      packageSize: 0,
      downloadUrls: const [],
      chunkManifestUrl: '',
      minimumSupportedVersion: '',
      minimumSupportedBuild: 0,
    );

ConsoleUpdate _service({
  required bool forceUpdate,
  int minimumSupportedBuild = 46308,
}) {
  return ConsoleUpdate(
    client: MockClient((_) async {
      return http.Response.bytes(
        utf8.encode(jsonEncode({
          'ok': true,
          'version_name': '4.3.13',
          'version_code': 46313,
          'release_notes': '修复了一些已知问题\n加入了一些功能',
          'apk_url': 'https://smartdolphinvpn.com/app.apk',
          'force_update': forceUpdate,
          'published': true,
          'minimum_supported_version': '4.3.8',
          'minimum_supported_build': minimumSupportedBuild,
        })),
        200,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      );
    }),
  );
}

void main() {
  test('same versionName uses Android versionCode for forced upgrades', () {
    expect(
      _release(version: '4.2.7', build: 46207).isNewerThan(
        currentVersion: '4.2.7',
        currentBuild: '46206',
      ),
      isTrue,
    );
  });

  test('lower versionCode never replaces a newer installed build', () {
    expect(
      _release(version: '9.0.0', build: 46206).isNewerThan(
        currentVersion: '4.2.7',
        currentBuild: '46207',
      ),
      isFalse,
    );
  });

  test('versionName remains the fallback when build is unavailable', () {
    expect(
      _release(version: '4.2.8', build: 46208).isNewerThan(
        currentVersion: '4.2.7',
        currentBuild: '',
      ),
      isTrue,
    );
  });

  test('unpublished releases are ignored', () {
    expect(
      _release(version: '4.2.8', build: 46208, published: false).isNewerThan(
        currentVersion: '4.2.7',
        currentBuild: '46207',
      ),
      isFalse,
    );
  });

  test('latest release remains optional for a supported client', () async {
    final update = await _service(forceUpdate: false).check(
      version: '4.3.12',
      build: '46312',
    );

    expect(update.forceUpdate, isFalse);
  });

  test('optional latest release is mandatory below the service floor',
      () async {
    final update = await _service(forceUpdate: false).check(
      version: '4.3.7',
      build: '46307',
    );

    expect(update.forceUpdate, isTrue);
    expect(update.minimumSupportedBuild, 46308);
  });

  test('server can explicitly force the latest release', () async {
    final update = await _service(forceUpdate: true).check(
      version: '4.3.12',
      build: '46312',
    );

    expect(update.forceUpdate, isTrue);
  });
}
