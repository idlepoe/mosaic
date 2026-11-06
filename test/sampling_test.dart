import 'package:flutter_test/flutter_test.dart';
import 'package:mosaic/models.dart';

void main() {
  test('still samples avoid the opening and final frame', () {
    expect(sampleTimes(100, 3), [25.0, 50.0, 75.0]);
  });
  test('clips fit even when the source is shorter than requested', () {
    for (final duration in [.2, 1.0, 2.0, 100.0]) {
      final clip = duration < 2 ? duration : 2.0;
      for (final start in sampleTimes(duration, 9, clip: clip)) {
        expect(start, greaterThanOrEqualTo(0));
        expect(start + clip, lessThanOrEqualTo(duration));
      }
    }
  });
  test('invalid durations have no samples', () {
    expect(sampleTimes(double.nan, 3), isEmpty);
    expect(sampleTimes(0, 3), isEmpty);
  });
  test('persisted settings roundtrip and sanitize filename suffix', () {
    final s = Settings()
      ..outputs = OutputKind.values.toSet()
      ..suffix = '../x:bad';
    final loaded = Settings.fromJson(s.toJson());
    expect(loaded.outputs, OutputKind.values.toSet());
    expect(loaded.suffix, 'xbad');
    expect(Settings.fromJson({'columns': 0, 'rows': 999}).columns, 1);
    expect(Settings.fromJson({'columns': 0, 'rows': 999}).rows, 6);
  });
}
