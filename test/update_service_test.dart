import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosaic/updates/update_service.dart';

class FakeTransport implements UpdateTransport {
  final Map<String, List<int>> responses;
  bool closed = false;
  FakeTransport(this.responses);
  @override
  Future<Stream<List<int>>> open(Uri uri) async {
    if (closed) throw const UpdateFailure('updateCancelled');
    final bytes = responses[uri.toString()]!;
    return Stream.fromIterable([
      for (var i = 0; i < bytes.length; i += 2)
        bytes.sublist(i, i + 2 > bytes.length ? bytes.length : i + 2),
    ]);
  }

  @override
  void close() => closed = true;
}

const app = InstalledApp(
  '1.4.0',
  2009,
  'com.mosaicvideo.mosaic',
  ['arm64-v8a'],
  '',
  true,
);
final payload = utf8.encode('synthetic APK fixture');
const assetUrl =
    'https://github.com/idlepoe/mosaic/releases/download/v1.4.1/Mosaic.apk';
Map<String, dynamic> release() => {
  'tag_name': 'v1.4.1',
  'body': 'Changes',
  'draft': false,
  'prerelease': false,
  'assets': [
    {
      'name': 'Mosaic.apk',
      'size': payload.length,
      'browser_download_url': assetUrl,
    },
  ],
};
Map<String, dynamic> manifest() => {
  'schema': 1,
  'version': '1.4.1',
  'packageName': app.packageName,
  'apks': [
    {
      'abi': 'arm64-v8a',
      'asset': 'Mosaic.apk',
      'size': payload.length,
      'sha256': sha256.convert(payload).toString(),
      'versionCode': 2010,
    },
  ],
};
AvailableUpdate update() => AvailableUpdate.parse(release(), manifest(), app)!;

void main() {
  test('numeric versions, installed build code and ABI select the update', () {
    expect(compareVersions('v1.10.0', '1.9.9'), greaterThan(0));
    expect(update().code, 2010);
    expect(update().uri.toString(), assetUrl);
    final same = InstalledApp(
      '1.4.1',
      2010,
      app.packageName,
      app.abis,
      '',
      true,
    );
    expect(AvailableUpdate.parse(release(), manifest(), same), isNull);
    final newer = InstalledApp(
      '1.5.0',
      2011,
      app.packageName,
      app.abis,
      '',
      true,
    );
    expect(AvailableUpdate.parse(release(), manifest(), newer), isNull);
  });
  test(
    'rejects incompatible ABI, wrong package, mismatched size, and foreign URLs',
    () {
      final badAbi = InstalledApp(
        app.version,
        app.code,
        app.packageName,
        ['x86_64'],
        '',
        true,
      );
      expect(
        () => AvailableUpdate.parse(release(), manifest(), badAbi),
        throwsA(isA<UpdateFailure>()),
      );
      final badPackage = manifest()..['packageName'] = 'another.app';
      expect(
        () => AvailableUpdate.parse(release(), badPackage, app),
        throwsA(isA<UpdateFailure>()),
      );
      final badSize = release();
      (badSize['assets'] as List).first['size'] = 1;
      expect(
        () => AvailableUpdate.parse(badSize, manifest(), app),
        throwsA(isA<UpdateFailure>()),
      );
      for (final url in [
        'http://github.com/idlepoe/mosaic/releases/download/v1/a.apk',
        'https://github.com/another/repo/releases/download/v1/a.apk',
        'https://evil.example/a.apk',
      ]) {
        expect(() => releaseAssetUri(url), throwsA(isA<UpdateFailure>()));
      }
    },
  );
  test('rejects prerelease and mismatched release version', () {
    expect(
      () => AvailableUpdate.parse(
        release()..['prerelease'] = true,
        manifest(),
        app,
      ),
      throwsA(isA<UpdateFailure>()),
    );
    expect(
      () => AvailableUpdate.parse(
        release(),
        manifest()..['version'] = '1.5.0',
        app,
      ),
      throwsA(isA<UpdateFailure>()),
    );
  });
  test(
    'check fetches release manifest and supports older releases without metadata',
    () async {
      const manifestUrl =
          'https://github.com/idlepoe/mosaic/releases/download/v1.4.1/mosaic-update.json';
      final data = release();
      (data['assets'] as List).add({
        'name': 'mosaic-update.json',
        'browser_download_url': manifestUrl,
      });
      final transport = FakeTransport({
        'https://api.github.com/repos/idlepoe/mosaic/releases/latest': utf8
            .encode(jsonEncode(data)),
        manifestUrl: utf8.encode(jsonEncode(manifest())),
      });
      expect((await UpdateClient(transport).check(app))!.code, 2010);
      final older = FakeTransport({
        'https://api.github.com/repos/idlepoe/mosaic/releases/latest': utf8
            .encode(jsonEncode(release()..['tag_name'] = 'v1.3.0')),
      });
      expect(await UpdateClient(older).check(app), isNull);
    },
  );
  test(
    'newer release without valid metadata cannot trigger download',
    () async {
      final client = UpdateClient(
        FakeTransport({
          'https://api.github.com/repos/idlepoe/mosaic/releases/latest': utf8
              .encode(jsonEncode(release())),
        }),
      );
      await expectLater(client.check(app), throwsA(isA<UpdateFailure>()));
    },
  );
  late Directory root;
  setUp(
    () async =>
        root = await Directory.systemTemp.createTemp('mosaic-update-test-'),
  );
  tearDown(() async => root.delete(recursive: true));
  test(
    'streams verified download to fixed private name and reports progress',
    () async {
      final progress = <int>[];
      final file = await UpdateClient(FakeTransport({assetUrl: payload}))
          .download(update(), root, (n, total) {
            expect(total, payload.length);
            progress.add(n);
          });
      expect(file.path.endsWith('update.apk'), isTrue);
      expect(await file.readAsBytes(), payload);
      expect(progress.last, payload.length);
      expect(File('${root.path}/update.apk.part').existsSync(), isFalse);
    },
  );
  for (final kind in ['hash', 'truncated', 'oversized', 'cancel']) {
    test(
      '$kind download is rejected and incomplete files are removed',
      () async {
        final bytes = switch (kind) {
          'hash' => List<int>.filled(payload.length, 0),
          'truncated' => payload.sublist(0, 3),
          'oversized' => [...payload, 1],
          _ => payload,
        };
        final client = UpdateClient(FakeTransport({assetUrl: bytes}));
        await expectLater(
          client.download(update(), root, (_, _) {
            if (kind == 'cancel') client.cancel();
          }),
          throwsA(isA<UpdateFailure>()),
        );
        expect(File('${root.path}/update.apk').existsSync(), isFalse);
        expect(File('${root.path}/update.apk.part').existsSync(), isFalse);
      },
    );
  }
}
