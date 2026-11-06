import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_flutter_new_full/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_full/return_code.dart';
import 'package:mosaic/models.dart';
import 'package:mosaic/processor.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native Android pipelines, output collisions and cancellation',
    (tester) async {
      final engine = MosaicProcessor()..begin();
      final temp = await (await getTemporaryDirectory()).createTemp(
        'mosaic_test_',
      );
      final created = <GeneratedFile>[];
      try {
        final input = '${temp.path}/mobile_port_test.mp4';
        await engine.run([
          '-f',
          'lavfi',
          '-i',
          'testsrc2=size=320x180:rate=8',
          '-t',
          '3',
          '-c:v',
          'mpeg4',
          input,
        ]);
        final item = QueueItem(input, 'mobile_port_test.mp4');
        final meta = await engine.probe(input);
        expect(meta.width, 320);
        expect(meta.height, 180);
        expect(meta.duration, closeTo(3, .1));
        final s = Settings()
          ..columns = 2
          ..rows = 1
          ..width = 640
          ..count = 2
          ..clipSeconds = .5
          ..fps = 4
          ..outputs = OutputKind.values.toSet();
        final first = await engine.generate(item, s, (_, _) {}, created.add);
        expect(first.length, 5);
        for (final result in first) {
          expect(await File(result.path).length(), greaterThan(100));
          if (result.path.endsWith('.jpg')) {
            final codec = await ui.instantiateImageCodec(
              await File(result.path).readAsBytes(),
            );
            final frame = await codec.getNextFrame();
            expect(frame.image.width, greaterThan(100));
            frame.image.dispose();
            codec.dispose();
          }
          final probe = await FFprobeKit.executeWithArguments([
            '-v',
            'error',
            '-count_frames',
            '-show_streams',
            '-of',
            'json',
            result.path,
          ]);
          expect(ReturnCode.isSuccess(await probe.getReturnCode()), isTrue);
          final output = await probe.getOutput() ?? '';
          // FFprobe cannot demux all animated WebP variants; verify those with Flutter.
          if (result.path.endsWith('.webp')) {
            final codec = await ui.instantiateImageCodec(
              await File(result.path).readAsBytes(),
            );
            expect(codec.frameCount, greaterThan(1));
            codec.dispose();
          } else {
            expect(output, contains('codec_name'));
          }
        }
        s.outputs = {OutputKind.sheet};
        final duplicate = await engine.generate(
          item,
          s,
          (_, _) {},
          created.add,
        );
        expect(duplicate.single.path, isNot(first.first.path));
        s.imageFormat = 'png';
        final png = await engine.generate(item, s, (_, _) {}, created.add);
        expect(png.single.path, endsWith('.png'));
        for (final format in ['gif', 'webm']) {
          s.outputs = {OutputKind.reel};
          s.animationFormat = format;
          final files = await engine.generate(item, s, (_, _) {}, created.add);
          expect(await File(files.single.path).length(), greaterThan(100));
          final m = await engine.probe(files.single.path);
          expect(m.duration, closeTo(1, .3));
        }
        final pending = engine.run([
          '-f',
          'lavfi',
          '-i',
          'testsrc2=size=1280x720:rate=30',
          '-t',
          '3600',
          '-f',
          'null',
          '-',
        ]);
        final assertion = expectLater(pending, throwsA(isA<JobCancelled>()));
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await engine.cancel();
        await assertion;
        engine.begin();
        expect((await engine.probe(input)).width, 320);
      } finally {
        for (final output in created) {
          final f = File(output.path);
          if (await f.exists()) await f.delete();
        }
        await temp.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
