import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ranch_management/main.dart';

Widget _host(Widget child, {MediaQueryData data = const MediaQueryData()}) =>
    MaterialApp(
      theme: appleTheme(),
      home: MediaQuery(
        data: data,
        child: Scaffold(body: Center(child: child)),
      ),
    );

void main() {
  testWidgets('Liquid Glass blurs content and turns solid for Increase '
      'Contrast', (tester) async {
    Widget glass() => const SizedBox(
      width: 200,
      height: 60,
      child: LiquidGlass(radius: 30, child: Text('Bar')),
    );
    await tester.pumpWidget(_host(glass()));
    expect(
      tester.widget<BackdropFilter>(find.byType(BackdropFilter)).enabled,
      isTrue,
    );

    await tester.pumpWidget(
      _host(glass(), data: const MediaQueryData(highContrast: true)),
    );
    expect(
      tester.widget<BackdropFilter>(find.byType(BackdropFilter)).enabled,
      isFalse,
    );
  });

  testWidgets('interactive glass reacts to touch and still taps, with and '
      'without Reduce Motion', (tester) async {
    for (final reduce in [false, true]) {
      var taps = 0;
      await tester.pumpWidget(
        _host(
          SizedBox.square(
            dimension: 56,
            child: LiquidGlass(
              radius: 28,
              onTap: () => taps++,
              child: const Icon(Icons.add),
            ),
          ),
          data: MediaQueryData(disableAnimations: reduce),
        ),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.add)),
      );
      // The first frame starts the spring; the second advances it.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      // The flex scale only exists when motion is allowed.
      final scaled = find.descendant(
        of: find.byType(LiquidGlass),
        matching: find.byWidgetPredicate(
          (w) => w is Transform && w.transform.getMaxScaleOnAxis() > 1.001,
        ),
      );
      expect(scaled, reduce ? findsNothing : findsOneWidget);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(taps, 1);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('edge-to-edge Shell leaves the bottom inset to the list', (
    tester,
  ) async {
    double? seen;
    Widget probe(bool edgeToEdge) => Shell(
      edgeToEdge: edgeToEdge,
      child: Builder(
        builder: (context) {
          seen = MediaQuery.paddingOf(context).bottom;
          return const SizedBox.expand();
        },
      ),
    );
    const data = MediaQueryData(
      size: Size(390, 800),
      padding: EdgeInsets.only(top: 47, bottom: 115),
    );
    await tester.pumpWidget(_host(probe(true), data: data));
    expect(seen, 115);
    await tester.pumpWidget(_host(probe(false), data: data));
    expect(seen, 0);
  });

  testWidgets('Apple sheet presents on a glass panel and dismisses', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showAppleSheet<void>(
              context: context,
              builder: (_) => const Padding(
                padding: EdgeInsets.all(21),
                child: Text('Sheet body'),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Sheet body'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('Sheet body'),
        matching: find.byType(BackdropFilter),
      ),
      findsOneWidget,
    );
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(find.text('Sheet body'), findsNothing);
  });
}
