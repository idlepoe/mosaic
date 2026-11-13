import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:mosaic/l10n/app_language.dart';
import 'package:mosaic/updates/update_dialog.dart';
import 'package:mosaic/updates/update_service.dart';
import 'support/studio_test_host.dart';

class FixtureTransport implements UpdateTransport {
  final List<int> bytes;
  FixtureTransport(this.bytes);
  @override
  Future<Stream<List<int>>> open(Uri uri) async => Stream.value(bytes);
  @override
  void close() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  final bytes = utf8.encode('synthetic download');
  late InstalledApp app;
  late AvailableUpdate update;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('mosaic-update-dialog-');
    app = InstalledApp(
      '1.4.0',
      2009,
      'com.mosaicvideo.mosaic',
      ['arm64-v8a'],
      root.path,
      true,
    );
    update = AvailableUpdate(
      '1.4.1',
      List.filled(20, 'Update notes').join('\n'),
      'Mosaic.apk',
      2010,
      bytes.length,
      sha256.convert(bytes).toString(),
      Uri.parse(
        'https://github.com/idlepoe/mosaic/releases/download/v1.4.1/Mosaic.apk',
      ),
    );
  });
  tearDown(() async {
    AppLanguage.instance.value = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppUpdater.channel, null);
    await root.delete(recursive: true);
  });
  Future<void> open(
    WidgetTester tester, {
    String language = 'en',
    double scale = 1,
    bool corrupt = false,
  }) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    AppLanguage.instance.value = Locale(language);
    await tester.runAsync(
      () => GlobalShadLocalizations.delegate.load(Locale(language)),
    );
    await tester.pumpWidget(
      StudioTestApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => UpdateDialog(
                  installed: app,
                  update: update,
                  clientFactory: () => UpdateClient(
                    FixtureTransport(
                      corrupt ? List.filled(bytes.length, 0) : bytes,
                    ),
                  ),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Future<void> download(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.tap(find.text(tr('updateDownload')));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
  }

  testWidgets(
    'verified download opens permission settings then retries installer',
    (tester) async {
      var installs = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AppUpdater.channel, (call) async {
            expect(call.method, 'install');
            expect(call.arguments['sha256'], update.hash);
            expect(call.arguments['code'], 2010);
            installs++;
            return installs == 1 ? 'permission' : 'installer';
          });
      await open(tester);
      await download(tester);
      expect(find.text(tr('updateVerified')), findsOneWidget);
      expect(File('${root.path}/update.apk').existsSync(), isTrue);
      await tester.tap(find.text(tr('updateInstall')));
      await tester.pumpAndSettle();
      expect(find.text(tr('updatePermissionHint')), findsOneWidget);
      await tester.tap(find.text(tr('updateInstall')));
      await tester.pumpAndSettle();
      expect(installs, 2);
      expect(find.text(tr('updatePermissionHint')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('failed verification offers download retry and no installation', (
    tester,
  ) async {
    await open(tester, corrupt: true);
    await download(tester);
    expect(find.text(tr('updateVerificationFailed')), findsOneWidget);
    expect(find.text(tr('updateInstall')), findsNothing);
    expect(find.text(tr('updateDownload')), findsOneWidget);
    expect(File('${root.path}/update.apk').existsSync(), isFalse);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'native rejection clears installation state and offers a fresh download',
    (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AppUpdater.channel, (_) async {
            throw PlatformException(code: 'UPDATE_VERIFY');
          });
      await open(tester);
      await download(tester);
      await tester.tap(find.text(tr('updateInstall')));
      await tester.pumpAndSettle();
      expect(find.text(tr('updateInstallFailed')), findsOneWidget);
      expect(find.text(tr('updateInstall')), findsNothing);
      expect(find.text(tr('updateDownload')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final language in ['ko', 'en', 'ja']) {
    testWidgets('$language update dialog supports large text', (tester) async {
      await open(tester, language: language, scale: 1.6);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
