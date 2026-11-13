import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:mosaic/main.dart';
import 'package:mosaic/models.dart';
import 'package:mosaic/l10n/app_language.dart';

void expectInsideClips(WidgetTester tester, Finder target, Rect painted) {
  var clips = 0;
  tester.element(target).visitAncestorElements((ancestor) {
    final render = ancestor.renderObject;
    if (render is RenderClipRect && render.clipBehavior != Clip.none) {
      clips++;
      final local =
          render.clipper?.getClip(render.size) ?? Offset.zero & render.size;
      final bounds = local.shift(render.localToGlobal(Offset.zero)).inflate(.1);
      expect(
        bounds.contains(painted.topLeft),
        isTrue,
        reason: '$painted outside $bounds',
      );
      expect(
        bounds.contains(painted.bottomRight),
        isTrue,
        reason: '$painted outside $bounds',
      );
    }
    return true;
  });
  expect(clips, greaterThan(0));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'settings keep endpoint thumbs and input focus rings inside clips',
    (tester) async {
      // Keep every group mounted while retaining a narrow phone width.
      // Ordinary phone-height scrolling is covered by theme_test.dart.
      tester.view.physicalSize = const Size(360, 12000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      AppLanguage.instance.value = const Locale('en');
      addTearDown(() => AppLanguage.instance.value = null);
      await GlobalShadLocalizations.delegate.load(const Locale('en'));
      final settings = Settings()
        ..outputs = OutputKind.values.toSet()
        ..fps = 15;
      SharedPreferences.setMockInitialValues({
        'settings': jsonEncode(settings.toJson()),
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => Directory.systemTemp.path,
          );
      await tester.pumpWidget(const MosaicApp());
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
      }
      await tester.pumpAndSettle();
      await tester.tap(find.text(tr('settings')));
      await tester.pumpAndSettle();
      final fps = find.byWidgetPredicate(
        (w) => w is ShadSlider && w.min == 4 && w.max == 15,
      );

      for (final end in [false, true]) {
        final track = tester.getRect(fps);
        await tester.tapAt(
          end
              ? track.centerRight - const Offset(1, 0)
              : track.centerLeft + const Offset(1, 0),
        );
        await tester.pumpAndSettle();
        expect(tester.widget<ShadSlider>(fps).initialValue, end ? 15 : 4);
        final circles = find.descendant(
          of: fps,
          matching: find.byWidgetPredicate(
            (w) =>
                w is Container &&
                w.decoration is BoxDecoration &&
                (w.decoration! as BoxDecoration).shape == BoxShape.circle,
          ),
        );
        expect(circles, findsWidgets);
        for (final element in circles.evaluate()) {
          final target = find.byElementPredicate((e) => identical(e, element));
          expectInsideClips(tester, target, tester.getRect(target));
        }
      }
      final input = find.byType(ShadInput);

      await tester.pumpAndSettle();
      await tester.tap(input);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<EditableText>(
              find.descendant(of: input, matching: find.byType(EditableText)),
            )
            .focusNode
            .hasFocus,
        isTrue,
      );
      expectInsideClips(tester, input, tester.getRect(input).inflate(6));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
