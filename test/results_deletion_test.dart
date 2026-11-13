import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:mosaic/main.dart';
import 'package:mosaic/l10n/app_language.dart';
import 'package:mosaic/ui/studio_components.dart';

Future<void> flushIo(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() async {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
  }
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late List<File> files;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('mosaic-bulk-delete-');
    final results = await Directory('${root.path}/results').create();
    files = [
      for (final name in ['a', 'b', 'c']) File('${results.path}/$name.webm'),
    ];
    for (final file in files) {
      await file.writeAsString('synthetic result');
    }
    await File('${root.path}/original.mp4').writeAsString('original video');
    await File('${root.path}/gallery-copy.webm').writeAsString('exported copy');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => root.path,
        );
  });
  tearDown(() async {
    AppLanguage.instance.value = null;
    await root.delete(recursive: true);
  });
  Future<void> open(
    WidgetTester tester, {
    String language = 'en',
    double scale = 1,
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
    await tester.runAsync(() async {
      await tester.pumpWidget(const MosaicApp());
    });
    await flushIo(tester);
    await tester.tap(find.text(tr('results')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(tr('selectResults')));
    await tester.pumpAndSettle();
  }

  Finder checkbox(File file) =>
      find.byKey(ValueKey('select-result:${p.normalize(file.path)}'));
  Future<void> tapText(WidgetTester tester, String key) async {
    await tester.tap(find.text(tr(key)).last);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'cancel preserves files; selected deletion leaves unselected and exported files intact',
    (tester) async {
      await open(tester);
      expect(
        tester
            .widget<StudioButton>(
              find.ancestor(
                of: find.text(tr('deleteSelected')),
                matching: find.byType(StudioButton),
              ),
            )
            .onPressed,
        isNull,
      );
      await tapText(tester, 'selectAllResults');
      expect(find.text(tr('selectedResultsCount', [3, 3])), findsOneWidget);
      await tapText(tester, 'clearResultSelection');
      expect(find.text(tr('selectedResultsCount', [0, 3])), findsOneWidget);
      for (final file in files.take(2)) {
        await tester.tapAt(
          tester.getTopLeft(checkbox(file)) + const Offset(8, 8),
        );
        await tester.pumpAndSettle();
      }
      await tapText(tester, 'deleteSelected');
      expect(find.text(tr('deleteSelectedResults', [2])), findsOneWidget);
      await tapText(tester, 'cancel2');
      expect(files.every((file) => file.existsSync()), isTrue);
      expect(find.text(tr('selectedResultsCount', [2, 3])), findsOneWidget);
      await tapText(tester, 'deleteSelected');
      await tapText(tester, 'delete');
      await flushIo(tester);
      expect(files[0].existsSync(), isFalse);
      expect(files[1].existsSync(), isFalse);
      expect(files[2].existsSync(), isTrue);
      expect(File('${root.path}/original.mp4').existsSync(), isTrue);
      expect(File('${root.path}/gallery-copy.webm').existsSync(), isTrue);
      expect(find.text(tr('selectResults')), findsOneWidget);
      // Existing single-result deletion uses the same confirmation and disk handling.
      await tester.tap(find.byTooltip(tr('deleteResult')));
      await tester.pumpAndSettle();
      await tapText(tester, 'delete');
      await flushIo(tester);
      expect(find.text(tr('completedResultsWillAppearHere')), findsOneWidget);
      expect(files[2].existsSync(), isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'partial failure retains failed selection and removes missing files from the list',
    (tester) async {
      await open(tester);
      await tapText(tester, 'selectAllResults');
      await tester.runAsync(() async {
        await files[1].delete();
        final blocked = await Directory(files[1].path).create();
        await File('${blocked.path}/keep').writeAsString('prevent deletion');
        await files[2].delete();
      });
      await tapText(tester, 'deleteSelected');
      await tapText(tester, 'delete');
      await flushIo(tester);
      expect(files[0].existsSync(), isFalse);
      expect(Directory(files[1].path).existsSync(), isTrue);
      expect(find.text(tr('selectedResultsCount', [1, 1])), findsOneWidget);
      expect(tester.widget<ShadCheckbox>(checkbox(files[1])).value, isTrue);
      expect(find.text(tr('resultsDeletePartial', [2, 1])), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('folder export blocks selection until the export finishes', (
    tester,
  ) async {
    await open(tester);
    await tapText(tester, 'cancel2');
    final export = Completer<bool>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('mosaic/storage'),
          (_) => export.future,
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('mosaic/storage'),
            null,
          ),
    );
    await tester.tap(find.byTooltip(tr('saveFileToAnotherLocation')).first);
    await tester.pumpAndSettle();
    final select = find.ancestor(
      of: find.text(tr('selectResults')),
      matching: find.byType(StudioButton),
    );
    expect(tester.widget<StudioButton>(select).onPressed, isNull);
    export.complete(false);
    await tester.pumpAndSettle();
    expect(tester.widget<StudioButton>(select).onPressed, isNotNull);
    expect(files.every((file) => file.existsSync()), isTrue);
    await tester.pumpWidget(const SizedBox());
  });
  for (final language in ['ko', 'en', 'ja']) {
    testWidgets('$language bulk controls fit narrow screens with large text', (
      tester,
    ) async {
      await open(tester, language: language, scale: 1.6);
      expect(tester.takeException(), isNull);
      await tapText(tester, 'selectAllResults');
      await tapText(tester, 'deleteSelected');
      expect(tester.takeException(), isNull);
      await tapText(tester, 'cancel2');
      await tapText(tester, 'cancel2');
      expect(find.text(tr('selectResults')), findsOneWidget);
      expect(files.every((file) => file.existsSync()), isTrue);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
