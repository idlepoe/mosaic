import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mosaic/main.dart';
import 'package:mosaic/l10n/app_language.dart';
import 'package:mosaic/ui/mascot.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLanguage.instance.value = const Locale('en');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => Directory.systemTemp.path,
        );
  });
  tearDown(() => AppLanguage.instance.value = null);
  Future<void> finishStartup(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
    }
    await tester.pumpAndSettle();
  }

  for (final size in [const Size(320, 568), const Size(800, 360)]) {
    testWidgets('mascot screens fit $size with enlarged text', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(const MosaicApp());
      await finishStartup(tester);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text(tr('settings')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text(tr('results')));
      await tester.pumpAndSettle();
      expect(find.byType(SingleChildScrollView), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('startup mascot is tied to initialization rather than a timer', (
    tester,
  ) async {
    final directory = Completer<String>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) => directory.future,
        );
    await tester.pumpWidget(const MosaicApp());
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(MascotStartup), findsOneWidget);
    directory.complete(Directory.systemTemp.path);
    await finishStartup(tester);
    expect(find.byType(MascotStartup), findsNothing);
    expect(find.text(tr('selectVideosFromGallery')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
