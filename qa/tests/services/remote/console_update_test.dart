import 'package:flutter_test/flutter_test.dart';
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
    );

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
}
