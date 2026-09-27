import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:ranch_management/main.dart';

void main() {
  late Directory dir;
  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('vimo_ui_fixes_');
    Hive.init(dir.path);
    for (final name in backupBoxNames) {
      await Hive.openBox(name);
    }
  });
  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });
  setUp(() async {
    for (final name in backupBoxNames) {
      await Hive.box(name).clear();
    }
    await Hive.box('settings').putAll({
      'languageMode': 'English',
      'currentRole': 'Admin',
      'currentUser': 'Appa',
      'deviceId': 'ui-test',
      'defaultMilkPrice': 60,
    });
  });

  Widget app(Widget home, {double scale = 1}) => MaterialApp(
    supportedLocales: const [Locale('en'), Locale('ta')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: home,
  );

  test('A member is not notified about their own ranch chat message', () {
    final own = {'title': 'Appa sent a message', 'addedBy': 'Appa'};
    final other = {'title': 'Amma sent a message', 'addedBy': 'Amma'};
    expect(notificationForMe(own, 'Appa'), isFalse);
    expect(notificationForMe(other, 'Appa'), isTrue);
    // Rows addressed to the member explicitly still show, even self-made.
    expect(
      notificationForMe({'targetUser': 'Appa', 'addedBy': 'Appa'}, 'Appa'),
      isTrue,
    );
    expect(notificationForMe({'targetUser': 'Amma'}, 'Appa'), isFalse);
    expect(
      notificationForMe({'localOnly': true, 'addedBy': 'Appa'}, 'Appa'),
      isTrue,
    );
  });

  testWidgets('Chat bubbles sit on their own side, not the centre', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      app(
        Scaffold(
          body: ListView(
            children: const [
              Column(
                children: [
                  AppleBubble(mine: true, child: Text('mine')),
                  AppleBubble(mine: false, child: Text('theirs')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    final mine = tester.getCenter(find.text('mine'));
    final theirs = tester.getCenter(find.text('theirs'));
    expect(mine.dx, greaterThan(300));
    expect(theirs.dx, lessThan(90));
  });

  testWidgets('Net result puts income left and expense right', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      app(
        const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(20),
            child: ProfitBar(income: 1200, expense: 400),
          ),
        ),
      ),
    );
    final income = tester.getTopLeft(find.text('Income'));
    final expense = tester.getTopRight(find.text('Expense'));
    expect(income.dx, lessThan(60));
    expect(expense.dx, greaterThan(330));
    expect(tester.takeException(), isNull);
  });

  for (final language in ['English', 'Tamil']) {
    testWidgets('$language vendor reports are clean and show no formulas', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await Hive.box('settings').put('languageMode', language);
        const provider = {'id': 'p', 'name': 'Kalai', 'kind': 'supplier'};
        const buyer = {'id': 'b', 'name': 'Vijay', 'kind': 'customer'};
        await Hive.box('vendor_people').put('p', provider);
        await Hive.box('vendor_people').put('b', buyer);
        await VendorLedger.record(
          id: 'in',
          person: provider,
          kind: 'collection',
          quantity: 5,
          price: 60,
        );
        await VendorLedger.record(
          id: 'out',
          person: buyer,
          kind: 'sale',
          quantity: 1,
          price: 60,
        );
      });
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        app(const Scaffold(body: VendorOnlyReports()), scale: 1.3),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Vijay'), findsOneWidget);
      expect(find.text('Kalai'), findsOneWidget);
      expect(find.textContaining('×'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('Top cow cards loop their animation and stop when hidden', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const cow = {'name': 'Lakshmi', 'id': '7', 'type': 'cow', 'key': 1};
    Future<void> show(bool visible) => tester.pumpWidget(
      app(
        Scaffold(
          body: TickerMode(
            enabled: visible,
            child: const SingleChildScrollView(
              child: RankedCowCard(animal: cow, rank: 1),
            ),
          ),
        ),
      ),
    );
    await show(true);
    RankTexturePainter painter() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((p) => p.painter)
        .whereType<RankTexturePainter>()
        .single;
    final start = painter().animation.value;
    await tester.pump(const Duration(seconds: 2));
    final later = painter().animation.value;
    expect(later, isNot(start));
    // Seven-second loop: it wraps around rather than stopping at the end.
    await tester.pump(const Duration(seconds: 6));
    expect(painter().animation.value, lessThan(later));
    await show(false);
    final paused = painter().animation.value;
    await tester.pump(const Duration(seconds: 1));
    expect(painter().animation.value, paused);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
