import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosaic/models.dart';
import 'package:mosaic/layout_controls.dart';

const video = VideoMetadata(120, 1920, 1080, 'h264', '', '');

void main() {
  test('automatic arrangement keeps direct rows and columns intact', () {
    final s = Settings()
      ..columns = 4
      ..rows = 5
      ..gridCount = 36
      ..autoArrange = true
      ..adaptiveCount = false;
    final samples = SamplePlan.create(s, video, OutputKind.sheet);
    final layout = SheetLayout.create(
      s,
      video,
      OutputKind.sheet,
      samples.count,
    );
    expect(samples.count, 36);
    expect(layout.columns * layout.rows, greaterThanOrEqualTo(36));
    expect(s.columns, 4);
    expect(s.rows, 5);
    s.autoArrange = false;
    expect(SamplePlan.create(s, video, OutputKind.sheet).count, 20);
    expect(s.gridCount, 36);
  });
  test('JPEG and WebP quality and per-output counts persist independently', () {
    final s = Settings()
      ..jpegQuality = 50
      ..webpQuality = 95
      ..screenshotCount = 8
      ..reelCount = 3
      ..adaptiveCount = false;
    final loaded = Settings.fromJson(s.toJson());
    expect(loaded.jpegQuality, 50);
    expect(loaded.webpQuality, 95);
    expect(SamplePlan.create(loaded, video, OutputKind.screenshots).count, 8);
    expect(SamplePlan.create(loaded, video, OutputKind.reel).count, 3);
    final legacy = Settings.fromJson({'quality': 70, 'count': 9});
    expect(legacy.jpegQuality, 70);
    expect(legacy.webpQuality, 70);
    expect(legacy.screenshotCount, 9);
    expect(legacy.reelCount, 9);
  });
  test(
    'irrelevant controls have explicit applicability and retain their values',
    () {
      final s = Settings()
        ..outputs = {OutputKind.reel}
        ..animationFormat = 'gif'
        ..header = true
        ..crop = true;
      expect(s.gridEnabled, isFalse);
      expect(s.stillEnabled, isFalse);
      expect(s.animationEnabled, isTrue);
      expect(s.webpQualityEnabled, isFalse);
      expect(s.timestampEnabled, isFalse);
      expect(s.previewKind, OutputKind.reel);
      expect(s.effectiveCrop, isFalse);
      expect(s.header, isTrue);
      expect(s.crop, isTrue);
      s.thumbnailAspect = '16:9';
      expect(s.effectiveCrop, isTrue);
      s.outputs.add(OutputKind.animatedSheet);
      expect(s.previewKind, OutputKind.animatedSheet);
      expect(s.webpQualityEnabled, isTrue);
    },
  );
  testWidgets(
    'automatic mode disables direct steppers and changes only its own capacity',
    (tester) async {
      final s = Settings()
        ..columns = 4
        ..rows = 5
        ..autoArrange = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (context, update) => LayoutControls(
                  settings: s,
                  metadata: video,
                  onChanged: () => update(() {}),
                ),
              ),
            ),
          ),
        ),
      );
      final plus = find.byTooltip('열 늘리기');
      await tester.ensureVisible(plus);
      expect(
        tester
            .widget<IconButton>(
              find.ancestor(of: plus, matching: find.byType(IconButton)).first,
            )
            .onPressed,
        isNull,
      );
      final preset = find.widgetWithText(ChoiceChip, '36개');
      await tester.ensureVisible(preset);
      await tester.tap(preset);
      await tester.pumpAndSettle();
      expect(s.gridCount, 36);
      expect(s.columns, 4);
      expect(s.rows, 5);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('non-grid output cannot change inactive canvas settings', (
    tester,
  ) async {
    final s = Settings()
      ..outputs = {OutputKind.screenshots}
      ..fitSheetWidth = false
      ..sheetAspect = '9:16';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: LayoutControls(
              settings: s,
              metadata: video,
              onChanged: () {},
            ),
          ),
        ),
      ),
    );
    final ratio = find.widgetWithText(ChoiceChip, '16:9').last;
    await tester.ensureVisible(ratio);
    await tester.tap(ratio, warnIfMissed: false);
    await tester.pump();
    expect(s.sheetAspect, '9:16');
    expect(tester.takeException(), isNull);
  });
}
