import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:mosaic/models.dart';
import 'package:mosaic/processor.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native 16-cell layout, portrait proportions and short-source adaptation',
    (tester) async {
      final engine = MosaicProcessor()..begin();
      final work = await (await getTemporaryDirectory()).createTemp(
        'mosaic_aspect_test_',
      );
      final generated = <GeneratedFile>[];
      Future<ui.Image> decode(String path) async {
        final codec = await ui.instantiateImageCodec(
          await File(path).readAsBytes(),
        );
        final image = (await codec.getNextFrame()).image;
        codec.dispose();
        return image;
      }

      try {
        final landscape = '${work.path}/landscape.mp4';
        await engine.run([
          '-f',
          'lavfi',
          '-i',
          'testsrc2=size=320x180:rate=4',
          '-t',
          '32',
          '-c:v',
          'mpeg4',
          landscape,
        ]);
        final item = QueueItem(landscape, 'aspect_16_test.mp4');
        final m = await engine.probe(landscape);
        final s = Settings()
          ..fitSheetWidth = false
          ..columns = 4
          ..rows = 4
          ..width = 640
          ..sheetAspect = '16:9'
          ..header = false
          ..clipSeconds = .5
          ..fps = 4
          ..imageFormat = 'png'
          ..outputs = {OutputKind.sheet, OutputKind.animatedSheet};
        expect(SamplePlan.create(s, m, OutputKind.animatedSheet).count, 16);
        final files = await engine.generate(item, s, (_, _) {}, generated.add);
        expect(files.length, 2);
        for (final file in files) {
          final image = await decode(file.path);
          expect(image.width, 640);
          expect(image.height, 360);
          image.dispose();
        }
        s.columns = 10;
        s.rows = 10;
        s.adaptiveCount = false;
        s.outputs = {OutputKind.animatedSheet};
        final hundred = await engine.generate(
          item,
          s,
          (_, _) {},
          generated.add,
        );
        final hundredFrame = await decode(hundred.single.path);
        expect(hundredFrame.width, 640);
        expect(hundredFrame.height, 360);
        hundredFrame.dispose();
        s.autoArrange = true;
        s.gridCount = 20;
        s.columns = 2;
        s.rows = 3;
        final automatic = await engine.generate(
          item,
          s,
          (_, _) {},
          generated.add,
        );
        final automaticFrame = await decode(automatic.single.path);
        expect(automaticFrame.width, 640);
        expect(automaticFrame.height, 360);
        automaticFrame.dispose();
        expect(s.columns, 2);
        expect(s.rows, 3);
        final portrait = '${work.path}/portrait.mp4';
        await engine.run([
          '-f',
          'lavfi',
          '-i',
          'testsrc2=size=180x320:rate=4',
          '-t',
          '2',
          '-c:v',
          'mpeg4',
          portrait,
        ]);
        final p = QueueItem(portrait, 'short_portrait_test.mp4');
        final pm = p.metadata = await engine.probe(portrait);
        final defaults = Settings()
          ..width = 640
          ..fps = 4
          ..imageFormat = 'png'
          ..outputs = OutputKind.values.toSet();
        for (final kind in OutputKind.values) {
          expect(SamplePlan.create(defaults, pm, kind).count, 1);
        }
        final short = await engine.generate(
          p,
          defaults,
          (_, _) {},
          generated.add,
        );
        expect(short.length, 4);
        for (final file in short) {
          final plan = SamplePlan.create(defaults, pm, file.kind);
          final expected = SheetLayout.create(
            defaults,
            pm,
            file.kind,
            plan.count,
          );
          final image = await decode(file.path);
          expect(image.width, expected.width);
          expect(image.height, expected.height);
          expect(
            expected.cellWidth / expected.cellHeight,
            closeTo(180 / 320, .01),
          );
          image.dispose();
        }
        // Reproduce the reported portrait-grid / wide-canvas gutters.
        final tallSource = '${work.path}/portrait_long.mp4';
        await engine.run([
          '-i',
          landscape,
          '-vf',
          'transpose=1',
          '-c:v',
          'mpeg4',
          tallSource,
        ]);
        final fitItem = QueueItem(tallSource, 'portrait_content_fit_test.mp4');
        final fitMetadata = fitItem.metadata = await engine.probe(tallSource);
        final fitSettings = Settings()
          ..columns = 4
          ..rows = 4
          ..width = 640
          ..sheetAspect = '16:9'
          ..clipSeconds = .5
          ..fps = 4
          ..imageFormat = 'png'
          ..outputs = {OutputKind.sheet, OutputKind.animatedSheet};
        final fittedFiles = await engine.generate(
          fitItem,
          fitSettings,
          (_, _) {},
          generated.add,
        );
        for (final file in fittedFiles) {
          final plan = SheetLayout.create(
            fitSettings,
            fitMetadata,
            file.kind,
            16,
          );
          expect(plan.left, 0);
          expect(plan.width, plan.gridWidth);
          final frame = await decode(file.path);
          expect(frame.width, 640);
          expect(frame.height, plan.gridHeight + plan.header);
          frame.dispose();
        }
        // Check rotation is applied before output geometry, not after stretching.
        final rotated = '${work.path}/rotated.mp4';
        // Write the ISO BMFF track matrix directly: rotation metadata flags
        // are not preserved by every native muxer build during stream copy.
        final bytes = await File(landscape).readAsBytes();
        var tkhd = -1;
        for (var i = 4; i < bytes.length - 80; i++) {
          if (bytes[i] == 0x74 &&
              bytes[i + 1] == 0x6b &&
              bytes[i + 2] == 0x68 &&
              bytes[i + 3] == 0x64) {
            tkhd = i;
            break;
          }
        }
        expect(tkhd, greaterThan(0));
        final matrixOffset = tkhd + 4 + (bytes[tkhd + 4] == 1 ? 52 : 40);
        final view = ByteData.sublistView(bytes);
        final matrix = [0, 65536, 0, -65536, 0, 0, 0, 0, 1073741824];
        for (var i = 0; i < 9; i++) {
          view.setInt32(matrixOffset + i * 4, matrix[i], Endian.big);
        }
        await File(rotated).writeAsBytes(bytes);
        final rm = await engine.probe(rotated);
        expect(rm.width, 180, reason: rm.raw);
        expect(rm.height, 320);
        final thumbnail = await engine.createThumbnail(rotated, rm);
        generated.add(GeneratedFile(thumbnail, OutputKind.screenshots));
        final thumbImage = await decode(thumbnail);
        expect(thumbImage.width / thumbImage.height, closeTo(180 / 320, .01));
        thumbImage.dispose();
        final r = QueueItem(rotated, 'rotation_test.mp4')..metadata = rm;
        defaults.outputs = {OutputKind.screenshots};
        defaults.count = 1;
        final rotationFiles = await engine.generate(
          r,
          defaults,
          (_, _) {},
          generated.add,
        );
        final image = await decode(rotationFiles.single.path);
        expect(image.width / image.height, closeTo(180 / 320, .01));
        image.dispose();
        // A selected 16:9 cell uses bars or cropping, never a stretched portrait.
        defaults.thumbnailAspect = '16:9';
        for (final crop in [false, true]) {
          defaults.crop = crop;
          final fitFiles = await engine.generate(
            p,
            defaults,
            (_, _) {},
            generated.add,
          );
          final frame = await decode(fitFiles.single.path);
          expect(frame.width / frame.height, closeTo(16 / 9, .04));
          frame.dispose();
        }
        final tiny = '${work.path}/single_frame.mp4';
        await engine.run([
          '-f',
          'lavfi',
          '-i',
          'testsrc2=size=320x180:rate=4',
          '-t',
          '0.1',
          '-c:v',
          'mpeg4',
          tiny,
        ]);
        final tinyItem = QueueItem(tiny, 'single_frame_test.mp4');
        final tinySettings = Settings()
          ..width = 320
          ..outputs = OutputKind.values.toSet();
        final tinyFiles = await engine.generate(
          tinyItem,
          tinySettings,
          (_, _) {},
          generated.add,
        );
        expect(tinyFiles.length, 4);
        for (final file in tinyFiles) {
          expect(await File(file.path).length(), greaterThan(100));
        }
      } finally {
        for (final output in generated) {
          final f = File(output.path);
          if (await f.exists()) await f.delete();
        }
        await work.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
