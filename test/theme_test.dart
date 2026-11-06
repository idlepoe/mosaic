import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:mosaic/main.dart';
import 'package:mosaic/l10n/app_language.dart';
import 'package:mosaic/ui/studio_components.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(
    () async => GlobalShadLocalizations.delegate.load(const Locale('ko')),
  );
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'settings': jsonEncode({
        'columns': 4,
        'rows': 5,
        'width': 1280,
        'outputs': ['sheet'],
      }),
    });
    AppLanguage.instance.value = const Locale('ko');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => Directory.systemTemp.path,
        );
  });
  tearDown(() => AppLanguage.instance.value = null);
  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets('$brightness supports large text and all three screens', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(const MosaicApp());
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final context = tester.element(find.byType(StudioNavigation));
      expect(Theme.of(context).brightness, brightness);
      expect(ShadTheme.of(context).brightness, brightness);
      await tester.tap(find.text(tr('settings')));
      await tester.pumpAndSettle();
      for (var i = 0; i < 10; i++) {
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -550));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      await tester.tap(find.text(tr('results')));
      await tester.pumpAndSettle();
      expect(find.text(tr('completedResultsWillAppearHere')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
