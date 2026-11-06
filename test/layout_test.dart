import 'support/studio_test_host.dart';
import 'package:mosaic/ui/studio_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosaic/models.dart';
import 'package:mosaic/layout_controls.dart';

const landscape = VideoMetadata(120, 1920, 1080, 'h264', '', '');
const portrait = VideoMetadata(120, 1080, 1920, 'h264', '', '');
VideoMetadata duration(double n) => VideoMetadata(n, 1920, 1080, '', '', '');

void main() {
  test(
    'content-fit portrait grids fill output width without outer gutters',
    () {
      final s = Settings()
        ..columns = 4
        ..rows = 4
        ..width = 1280
        ..sheetAspect = '16:9'
        ..adaptiveCount = false;
      const video = VideoMetadata(143, 720, 1280, 'h264', '', '');
      final layout = SheetLayout.create(s, video, OutputKind.sheet, 16);
      expect(layout.left, 0);
      expect(layout.gridWidth, layout.width);
      expect(layout.width, 1280);
      expect(layout.height, layout.gridHeight + layout.header);
      expect(layout.cellWidth / layout.cellHeight, closeTo(720 / 1280, .01));
    },
  );
  test(
    'old settings migrate to content fit instead of retaining wide black bars',
    () {
      expect(
        Settings.fromJson({
          'sheetAspect': '16:9',
          'columns': 4,
          'rows': 4,
        }).fitSheetWidth,
        isTrue,
      );
    },
  );
  test(
    'a single-frame source seeks at zero rather than beyond its last frame',
    () {
      const m = VideoMetadata(
        .25,
        320,
        180,
        'mpeg4',
        '',
        '',
        frameSeconds: .25,
      );
      expect(SamplePlan.create(Settings(), m, OutputKind.sheet).times, [0.0]);
    },
  );
  test('short sources reduce every output instead of repeating nine cells', () {
    final s = Settings()
      ..columns = 3
      ..rows = 3;
    for (final kind in OutputKind.values) {
      for (final seconds in [.2, .5, 1.0, 2.0, 3.0]) {
        final plan = SamplePlan.create(s, duration(seconds), kind);
        expect(plan.count, 1);
        expect(plan.times.single + plan.clip, lessThanOrEqualTo(seconds));
      }
    }
  });
  test('adaptive counts grow with duration and remain upper bounded', () {
    final s = Settings()
      ..columns = 10
      ..rows = 10;
    expect(SamplePlan.create(s, duration(10), OutputKind.sheet).count, 5);
    expect(
      SamplePlan.create(s, duration(32), OutputKind.animatedSheet).count,
      16,
    );
    expect(
      SamplePlan.create(s, duration(500), OutputKind.animatedSheet).count,
      100,
    );
  });
  test('automatic clips do not overlap or extend beyond the source', () {
    final s = Settings()
      ..columns = 10
      ..rows = 10;
    for (final seconds in [2.0, 4.0, 13.0, 32.0, 100.0]) {
      final plan = SamplePlan.create(
        s,
        duration(seconds),
        OutputKind.animatedSheet,
      );
      for (var i = 0; i < plan.count; i++) {
        expect(plan.times[i] + plan.clip, lessThanOrEqualTo(seconds));
        if (i > 0) {
          expect(
            plan.times[i] - plan.times[i - 1],
            greaterThanOrEqualTo(plan.clip - .000001),
          );
        }
      }
    }
  });
  test('even manual mode cannot duplicate a single full-length clip', () {
    final s = Settings()..adaptiveCount = false;
    expect(SamplePlan.create(s, duration(1), OutputKind.animatedSheet).times, [
      0.0,
    ]);
  });
  test(
    'source proportions remain landscape or portrait independently of grid',
    () {
      final s = Settings()..adaptiveCount = false;
      for (final m in [landscape, portrait]) {
        final layout = SheetLayout.create(s, m, OutputKind.sheet, 12);
        expect(
          layout.cellWidth / layout.cellHeight,
          closeTo(m.width / m.height, .02),
        );
      }
    },
  );
  test('explicit canvas and individual cell aspect ratios are independent', () {
    final s = Settings()
      ..fitSheetWidth = false
      ..sheetAspect = '9:16'
      ..thumbnailAspect = '16:9'
      ..adaptiveCount = false;
    final layout = SheetLayout.create(s, portrait, OutputKind.sheet, 12);
    expect(layout.width / layout.height, closeTo(9 / 16, .002));
    expect(layout.cellWidth / layout.cellHeight, closeTo(16 / 9, .025));
    expect(layout.left, greaterThanOrEqualTo(0));
    expect(layout.top, greaterThanOrEqualTo(layout.header));
    expect(layout.left + layout.gridWidth, lessThanOrEqualTo(layout.width));
    expect(layout.top + layout.gridHeight, lessThanOrEqualTo(layout.height));
  });
  test('100-cell grids use bounded memory and valid even dimensions', () {
    final s = Settings()
      ..columns = 10
      ..rows = 10
      ..adaptiveCount = false;
    for (final m in [landscape, portrait]) {
      final layout = SheetLayout.create(s, m, OutputKind.animatedSheet, 100);
      expect(layout.width * layout.height, lessThanOrEqualTo(8000000));
      expect(layout.height, lessThanOrEqualTo(8192));
      expect(layout.cellWidth % 2, 0);
      expect(layout.cellHeight % 2, 0);
    }
  });
  test('reduced counts compact the grid instead of filling unused cells', () {
    final layout = SheetLayout.create(
      Settings(),
      duration(2),
      OutputKind.sheet,
      1,
    );
    expect(layout.columns, 1);
    expect(layout.rows, 1);
  });
  test('rotation and anamorphic SAR normalize displayed dimensions', () {
    final m = parseVideoMetadata({
      'format': {'duration': '30'},
      'streams': [
        {
          'codec_type': 'video',
          'width': 720,
          'height': 576,
          'sample_aspect_ratio': '16:15',
          'side_data_list': [
            {'rotation': -90},
          ],
        },
      ],
    });
    expect(m.width, 576);
    expect(m.height, 768);
  });
  test('native rotation supplements missing FFprobe side data', () {
    final m = parseVideoMetadata({
      'format': {'duration': '2'},
      'mosaic_android_rotation': 90,
      'streams': [
        {'codec_type': 'video', 'width': 320, 'height': 180},
      ],
    });
    expect(m.width, 180);
    expect(m.height, 320);
  });
  test('every count preset retains its exact selected capacity', () {
    for (final count in [4, 9, 12, 16, 20, 24, 36, 48, 64, 100]) {
      final cols = bestColumns(count, 9 / 16, 16 / 9, exact: true);
      expect(count % cols, 0);
      expect(count ~/ cols, lessThanOrEqualTo(10));
    }
  });
  testWidgets('layout controls fit a phone and update ratio selection', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final s = Settings()..fitSheetWidth = false;
    var changed = 0;
    await tester.pumpWidget(
      StudioTestApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: LayoutControls(
                settings: s,
                metadata: landscape,
                onChanged: () => changed++,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final chip = find.widgetWithText(StudioChoice, '9:16').first;
    await tester.ensureVisible(chip);
    await tester.tap(chip);
    await tester.pump();
    expect(s.thumbnailAspect, '9:16');
    expect(changed, 1);
    expect(tester.takeException(), isNull);
    final canvasChip = find.widgetWithText(StudioChoice, '16:9').last;
    await tester.ensureVisible(canvasChip);
    await tester.tap(canvasChip);
    await tester.pump();
    expect(s.sheetAspect, '16:9');
    expect(s.columns, 3);
    expect(s.rows, 4);
    expect(s.columns * s.rows, 12);
    expect(tester.takeException(), isNull);
  });
}
