import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosaic/ui/mascot.dart';
import 'support/studio_test_host.dart';

void main() {
  Widget loading({
    bool reduced = false,
    bool active = true,
    bool visible = true,
  }) => StudioTestApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduced),
      child: TickerMode(
        enabled: visible,
        child: Scaffold(
          body: Center(child: LoadingMascot(size: 140, active: active)),
        ),
      ),
    ),
  );
  testWidgets('the loose tile moves independently during loading', (
    tester,
  ) async {
    await tester.pumpWidget(loading());
    await tester.pump(const Duration(milliseconds: 100));
    final before = tester.widget<Positioned>(
      find.byKey(const ValueKey('mascot-loading-tile')),
    );
    await tester.pump(const Duration(milliseconds: 600));
    final after = tester.widget<Positioned>(
      find.byKey(const ValueKey('mascot-loading-tile')),
    );
    expect(after.top, isNot(before.top));
    expect(after.left, isNot(before.left));
    expect(find.byType(MascotArt), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'reduced motion keeps a stable completed tile and no repeating ticker',
    (tester) async {
      await tester.pumpWidget(loading(reduced: true));
      await tester.pumpAndSettle();
      final before = tester.widget<Positioned>(
        find.byKey(const ValueKey('mascot-loading-tile')),
      );
      await tester.pump(const Duration(seconds: 2));
      final after = tester.widget<Positioned>(
        find.byKey(const ValueKey('mascot-loading-tile')),
      );
      expect(after.top, before.top);
      expect(after.left, before.left);
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'inactive and hidden loaders stop and resume without leaking tickers',
    (tester) async {
      await tester.pumpWidget(loading());
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpWidget(loading(active: false));
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.pumpWidget(loading(visible: false));
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.pumpWidget(loading());
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.binding.hasScheduledFrame, isTrue);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'all six assets decode and fit together without text in the artwork',
    (tester) async {
      await tester.pumpWidget(
        StudioTestApp(
          home: Scaffold(
            body: Wrap(
              children: [
                for (final pose in MascotPose.values) MascotArt(pose, size: 80),
              ],
            ),
          ),
        ),
      );
      final context = tester.element(find.byType(Wrap).first);
      await tester.runAsync(() async {
        for (final pose in MascotPose.values) {
          await precacheImage(
            AssetImage('assets/mascot/${pose.name}.png'),
            context,
          );
        }
      });
      await tester.pumpAndSettle();
      expect(find.byType(MascotArt), findsNWidgets(6));
      expect(find.byType(ExcludeSemantics), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
}
