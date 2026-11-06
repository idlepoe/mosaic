import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:mosaic/models.dart';
import 'package:mosaic/processor.dart';

// Opt-in because this intentionally leaves synthetic outputs in the gallery.
// Run on API 29+; legacy storage permission dialogs need manual interaction.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'save JPEG PNG animated WebP GIF and WebM through MediaStore',
    (tester) async {
      final engine = MosaicProcessor()..begin();
      final work = await (await getTemporaryDirectory()).createTemp(
        'mosaic_gallery_',
      );
      final outputs = <GeneratedFile>[];
      try {
        final input = '${work.path}/mosaic_gallery_test.mp4';
        await engine.run([
          '-f',
          'lavfi',
          '-i',
          'testsrc2=size=320x180:rate=4',
          '-t',
          '2',
          '-c:v',
          'mpeg4',
          input,
        ]);
        final item = QueueItem(input, 'mosaic_gallery_test.mp4');
        final settings = Settings()
          ..width = 320
          ..columns = 1
          ..rows = 1
          ..count = 1
          ..clipSeconds = .5
          ..fps = 4
          ..header = false;
        settings.outputs = {OutputKind.sheet, OutputKind.animatedSheet};
        await engine.generate(item, settings, (_, _) {}, outputs.add);
        settings.imageFormat = 'png';
        settings.outputs = {OutputKind.sheet};
        await engine.generate(item, settings, (_, _) {}, outputs.add);
        for (final format in ['gif', 'webm']) {
          settings.outputs = {OutputKind.reel};
          settings.animationFormat = format;
          await engine.generate(item, settings, (_, _) {}, outputs.add);
        }
        expect(outputs.length, 5);
        for (final file in outputs) {
          final result = await const MethodChannel(
            'mosaic/gallery',
          ).invokeMapMethod<String, dynamic>('save', {'path': file.path});
          expect(result?['uri'], startsWith('content://media/'));
          expect(result?['album'], 'Mosaic');
        }
      } finally {
        for (final file in outputs) {
          if (await File(file.path).exists()) await File(file.path).delete();
        }
        await work.delete(recursive: true);
      }
    },
    skip: !const bool.fromEnvironment('MOSAIC_GALLERY_TEST'),
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
