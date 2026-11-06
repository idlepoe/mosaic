import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mosaic/main.dart';
import 'package:mosaic/models.dart';
import 'package:mosaic/l10n/app_language.dart';
import 'package:mosaic/l10n/catalogs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLanguage.instance.value = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => Directory.systemTemp.path,
        );
  });
  tearDown(() => AppLanguage.instance.value = null);

  test('all catalogs have complete keys and matching placeholders', () {
    final english = translations['en']!;
    Set<String> placeholders(String s) =>
        RegExp(r'\{\d+\}').allMatches(s).map((m) => m[0]!).toSet();
    for (final code in ['en', 'ko', 'ja']) {
      expect(translations[code]!.keys.toSet(), english.keys.toSet());
      expect(
        jsonDecode(File('lib/l10n/$code.json').readAsStringSync()),
        translations[code],
      );
      for (final entry in translations[code]!.entries) {
        expect(entry.value.trim(), isNotEmpty, reason: '$code/${entry.key}');
        expect(
          placeholders(entry.value),
          placeholders(english[entry.key]!),
          reason: '$code/${entry.key}',
        );
      }
    }
  });
  test(
    'regional locales, preferred languages, and English fallback resolve',
    () {
      expect(
        AppLanguage.resolve(null, [const Locale('ja', 'JP')]),
        const Locale('ja'),
      );
      expect(
        AppLanguage.resolve(null, [
          const Locale('fr'),
          const Locale('ko', 'KR'),
        ]),
        const Locale('ko'),
      );
      expect(
        AppLanguage.resolve(null, [const Locale('fr')]),
        const Locale('en'),
      );
      expect(
        AppLanguage.resolve(const Locale('en'), [const Locale('ko')]),
        const Locale('en'),
      );
    },
  );
  test(
    'language persists separately and system choice removes override',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('settings', '{"width":1920}');
      await AppLanguage.instance.select(const Locale('ja'));
      AppLanguage.instance.value = null;
      await AppLanguage.instance.load();
      expect(AppLanguage.instance.value, const Locale('ja'));
      expect(prefs.getString('settings'), '{"width":1920}');
      await AppLanguage.instance.select(null);
      expect(prefs.containsKey(AppLanguage.preferenceKey), isFalse);
      await prefs.setString(AppLanguage.preferenceKey, 'unsupported');
      await AppLanguage.instance.load();
      expect(AppLanguage.instance.value, isNull);
    },
  );
  test('queued statuses and native errors follow the current language', () {
    final item = QueueItem('private.mp4', 'private');
    item.setStatus(
      'failed',
      PlatformException(code: 'PERMISSION', message: 'native diagnostic'),
    );
    AppLanguage.instance.value = const Locale('en');
    expect(item.status, contains('Storage permission'));
    expect(item.status, isNot(contains('native diagnostic')));
    AppLanguage.instance.value = const Locale('ja');
    expect(item.status, contains('権限'));
    expect(tr('preview', ['file {0}']), 'プレビュー · file {0}');
  });
  for (final code in ['ko', 'en', 'ja']) {
    testWidgets('$code phone layout and live language selector', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      AppLanguage.instance.value = Locale(code);
      await tester.pumpWidget(const MosaicApp());
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(find.text(tr('videos')), findsOneWidget);
      await tester.tap(find.text(tr('settings')));
      await tester.pumpAndSettle();
      // The settings tree lays out every group, including long translated labels.
      expect(find.text(tr('frameAspectRatio')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byIcon(Icons.language));
      await tester.pumpAndSettle();
      await tester.tap(find.text(code == 'en' ? '日本語' : 'English'));
      await tester.pumpAndSettle();
      expect(find.text(code == 'en' ? '設定' : 'Settings'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
