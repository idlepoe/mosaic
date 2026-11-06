import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mosaic/main.dart';
import 'package:mosaic/models.dart';
import 'package:mosaic/processor.dart';
import 'package:mosaic/l10n/app_language.dart';
import 'package:mosaic/ui/mascot.dart';
import 'package:mosaic/ui/studio_components.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'real encoding with loading, completion, cancellation and import error mascot',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final originalSettings = prefs.getString('settings');
      final originalLocale = AppLanguage.instance.value;
      final base = 'mascot_ui_${DateTime.now().microsecondsSinceEpoch}';
      final temp = await (await getTemporaryDirectory()).createTemp(
        'mascot_ui_',
      );
      final results = Directory(
        p.join((await getApplicationDocumentsDirectory()).path, 'results'),
      );
      var importFails = false;
      const record = bool.fromEnvironment('MOSAIC_RECORD_UI');
      Future<void> capture(String name) async {
        if (!record) return;
        await tester.pump(const Duration(milliseconds: 120));
        final directory = Directory(
          p.join(
            (await getExternalStorageDirectory())!.path,
            'mascot-evidence',
          ),
        );
        await directory.create(recursive: true);
        await File(
          p.join(directory.path, '$name.png'),
        ).writeAsBytes(await binding.takeScreenshot(name));
      }

      final channel = const MethodChannel('mosaic/gallery');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      Future<void> until(bool Function() done, {int seconds = 90}) async {
        final end = DateTime.now().add(Duration(seconds: seconds));
        while (!done() && DateTime.now().isBefore(end)) {
          await tester.pump(const Duration(milliseconds: 150));
        }
        expect(
          done(),
          isTrue,
          reason: 'UI state did not arrive within $seconds seconds',
        );
      }

      Finder pose(MascotPose value) =>
          find.byWidgetPredicate((w) => w is MascotArt && w.pose == value);
      try {
        final source = p.join(temp.path, '$base.mp4');
        await (MosaicProcessor()..begin()).run([
          '-f',
          'lavfi',
          '-i',
          'testsrc2=size=640x360:rate=12',
          '-t',
          '12',
          '-c:v',
          'mpeg4',
          source,
        ]);
        final settings = Settings()
          ..columns = 3
          ..rows = 2
          ..width = record ? 960 : 640
          ..adaptiveCount = false
          ..clipSeconds = .5
          ..fps = record ? 8 : 4
          ..outputs = {OutputKind.sheet, OutputKind.animatedSheet};
        await prefs.setString('settings', jsonEncode(settings.toJson()));
        AppLanguage.instance.value = const Locale('en');
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'pickVideos') {
            if (importFails) {
              throw PlatformException(
                code: 'IMPORT',
                message: 'Injected import failure',
              );
            }
            return [
              {'path': source, 'name': '$base.mp4', 'id': base},
            ];
          }
          throw PlatformException(code: 'UNEXPECTED', message: call.method);
        });
        await tester.pumpWidget(const MosaicApp());
        await until(
          () => find.text(tr('selectVideosFromGallery')).evaluate().isNotEmpty,
        );
        if (record) {
          await binding.convertFlutterSurfaceToImage();
          await tester.pump();
        }
        await tester.tap(find.text(tr('selectVideosFromGallery')));
        final create = find.widgetWithText(
          StudioButton,
          tr('createFromVideoS', [1]),
        );
        await until(
          () =>
              create.evaluate().isNotEmpty &&
              tester.widget<StudioButton>(create).onPressed != null,
        );
        await tester.tap(create);
        await tester.pump(const Duration(milliseconds: 150));
        expect(find.byType(LoadingMascot), findsOneWidget);
        await capture('01-loading');
        await until(() => pose(MascotPose.complete).evaluate().isNotEmpty);
        expect(find.text(tr('mascotCompleted', [2])), findsOneWidget);
        await capture('02-complete');
        expect(
          await results
              .list()
              .where((f) => p.basename(f.path).startsWith(base))
              .length,
          2,
        );
        // Keep a brief stable completion state available for a scrcpy inspection.
        await tester.pump(const Duration(seconds: 3));
        await tester.tap(find.text(tr('results')));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(LoadingMascot), findsNothing);
        await capture('03-results');
        await tester.tap(find.text(tr('videos')));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(create);
        await tester.pump(const Duration(milliseconds: 150));
        final cancel = find.byWidgetPredicate(
          (w) =>
              w is StudioButton &&
              w.icon is Icon &&
              (w.icon! as Icon).icon == Icons.stop_rounded,
        );
        expect(cancel, findsOneWidget);
        await tester.tap(cancel);
        await until(
          () => find
              .text(tr('processingCanceledCompletedResultsAreRetained'))
              .evaluate()
              .isNotEmpty,
        );
        expect(find.byType(LoadingMascot), findsNothing);
        await capture('04-cancelled');
        // Move to the top of the queue before selecting a file again.
        await tester.drag(find.byType(Scrollable).first, const Offset(0, 2000));
        await tester.pump(const Duration(milliseconds: 400));
        importFails = true;
        await tester.tap(find.text(tr('selectVideosFromGallery')));
        await until(
          () => pose(MascotPose.error).evaluate().isNotEmpty,
          seconds: 15,
        );
        expect(
          find.textContaining('Could not import the video'),
          findsOneWidget,
        );
        await capture('05-error');
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        messenger.setMockMethodCallHandler(channel, null);
        if (originalSettings == null) {
          await prefs.remove('settings');
        } else {
          await prefs.setString('settings', originalSettings);
        }
        AppLanguage.instance.value = originalLocale;
        if (await results.exists()) {
          await for (final file in results.list()) {
            if (file is File && p.basename(file.path).startsWith(base)) {
              await file.delete();
            }
          }
        }
        if (await temp.exists()) await temp.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
