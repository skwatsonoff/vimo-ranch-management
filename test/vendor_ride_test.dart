import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:ranch_management/main.dart';

void main() {
  late Directory dir;
  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('vimo_ride_');
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
      'deviceId': 'ride-test',
      'defaultMilkPrice': 60,
    });
  });
  Map<String, dynamic> person(
    String id, {
    String kind = 'customer',
    String cycle = 'Daily',
  }) => {
    'id': id,
    'cloudId': id,
    'kind': kind,
    'name': id,
    'place': 'Erode',
    'quantity': 2.0,
    'price': 60.0,
    'days': <int>[],
    'sessions': ['Morning', 'Evening'],
    'paymentCycle': cycle,
  };
  test(
    'Optional milk days include both sessions; explicit days restrict them',
    () {
      final p = person('A');
      expect(vendorScheduled(p, DateTime(2026, 9, 27), 'Morning'), true);
      expect(
        vendorScheduled(
          {
            ...p,
            'days': [1],
          },
          DateTime(2026, 9, 27),
          'Morning',
        ),
        false,
      );
      expect(
        vendorScheduled(
          {
            ...p,
            'sessions': ['Evening'],
          },
          DateTime(2026, 9, 27),
          'Morning',
        ),
        false,
      );
    },
  );
  test('Payment schedule rolls over weeks and short calendar months', () {
    expect(
      vendorPaymentDate({
        'paymentCycle': 'Weekly',
        'paymentDays': [0],
      }, DateTime(2026, 9, 26)),
      DateTime(2026, 9, 27),
    );
    expect(
      vendorPaymentDate({
        'paymentCycle': 'Flexible',
        'paymentDays': [1, 3],
      }, DateTime(2026, 9, 24)),
      DateTime(2026, 9, 28),
    );
    expect(
      vendorPaymentDate({
        'paymentCycle': 'Monthly',
        'paymentMonthDay': 31,
      }, DateTime(2026, 2, 27)),
      DateTime(2026, 2, 28),
    );
    expect(
      vendorPaymentDate({
        'paymentCycle': 'Monthly',
        'paymentMonthDay': 10,
      }, DateTime(2026, 12, 11)),
      DateTime(2027, 1, 10),
    );
  });
  test(
    'Customer order differs by day; supplier ranking differs by session',
    () {
      final a = {
        ...person('A'),
        'routeOrder': {'0': 1, '1': 0},
      };
      final b = {
        ...person('B'),
        'routeOrder': {'0': 0, '1': 1},
      };
      expect(
        vendorRoutePeople(
          [a, b],
          [],
          DateTime(2026, 9, 27),
          'Morning',
        ).map((p) => p['id']),
        ['B', 'A'],
      );
      expect(
        vendorRoutePeople(
          [a, b],
          [],
          DateTime(2026, 9, 28),
          'Morning',
        ).map((p) => p['id']),
        ['A', 'B'],
      );
      final suppliers = [
        person('A', kind: 'supplier'),
        person('B', kind: 'supplier'),
      ];
      final rows = [
        {
          'personId': 'A',
          'kind': 'collection',
          'quantity': 10,
          'session': 'Morning',
        },
        {
          'personId': 'B',
          'kind': 'purchase',
          'quantity': 20,
          'session': 'Evening',
        },
      ];
      expect(
        vendorRoutePeople(
          suppliers,
          rows,
          DateTime(2026, 9, 27),
          'Morning',
          suppliers: true,
        ).first['id'],
        'A',
      );
      expect(
        vendorRoutePeople(
          suppliers,
          rows,
          DateTime(2026, 9, 27),
          'Evening',
          suppliers: true,
        ).first['id'],
        'B',
      );
    },
  );
  test('Ride and hardware preferences remain local to the device', () {
    expect(CloudSyncService.isLocalSetting('vendorRide_ranch_user'), true);
    expect(
      CloudSyncService.isLocalSetting('vendorRide_ranch_user_volume'),
      true,
    );
    expect(CloudSyncService.isLocalSetting('defaultMilkPrice'), false);
  });
  Future<void> mountRide(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(
      () => Hive.box('vendor_people').put('Kumar', person('Kumar')),
    );
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: VendorRideScreen())),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.runAsync(() async {
      await tester.tap(find.text('Start'));
      await Future<void>.delayed(const Duration(milliseconds: 40));
    });
    await tester.pump(const Duration(milliseconds: 1900));
  }

  testWidgets(
    'Start and untouched End leave milk, people and ledger unchanged',
    (tester) async {
      await mountRide(tester);
      final people = Hive.box('vendor_people').toMap().toString();
      await tester.ensureVisible(find.text('End'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('End'));
        await Future<void>.delayed(const Duration(milliseconds: 40));
      });
      await tester.pump(const Duration(milliseconds: 500));
      expect(Hive.box('vendor_entries').isEmpty, true);
      expect(Hive.box('vendor_people').toMap().toString(), people);
      expect(find.byType(VendorRideSummary), findsNothing);
      expect(find.text('Start'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('Left swipe edits; a second swipe skips without a sale', (
    tester,
  ) async {
    await mountRide(tester);
    final card = find
        .ancestor(of: find.text('Kumar'), matching: find.byType(Glass))
        .first;
    await tester.drag(card, const Offset(-150, 0));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Litres'), findsOneWidget);
    expect(Hive.box('vendor_entries').isEmpty, true);
    await tester.runAsync(() async {
      await tester.drag(card, const Offset(-150, 0));
      await Future<void>.delayed(const Duration(milliseconds: 40));
    });
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Skipped today'), findsOneWidget);
    expect(Hive.box('vendor_entries').isEmpty, true);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'Completed ride deducts milk once and collects the previous balance',
    (tester) async {
      await tester.runAsync(() async {
        await Hive.box('vendor_entries').putAll({
          'supply': {
            'cloudId': 'supply',
            'kind': 'collection',
            'stockScope': 'vendor_v2',
            'quantity': 10,
            'amount': 400,
            'paid': 400,
            'personId': 'supplier',
          },
          'old-sale': {
            'cloudId': 'old-sale',
            'kind': 'sale',
            'stockScope': 'vendor_v2',
            'quantity': 1,
            'amount': 60,
            'paid': 0,
            'personId': 'Kumar',
          },
        });
      });
      await mountRide(tester);
      final card = find
          .ancestor(of: find.text('Kumar'), matching: find.byType(Glass))
          .first;
      await tester.runAsync(() async {
        await tester.drag(card, const Offset(160, 0));
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Received'), findsOneWidget);
      expect(vendorMilkBalance(vendorRows('vendor_entries')), 7);
      expect(vendorPersonDue('Kumar', vendorRows('vendor_entries')), 0);
      await tester.runAsync(() async {
        await Hive.box('settings').flush();
        await Hive.box('vendor_entries').flush();
        await Future<void>.delayed(const Duration(milliseconds: 120));
      });
      await tester.pumpAndSettle();
      final count = Hive.box('vendor_entries').length;
      await tester.drag(card, const Offset(160, 0));
      await tester.pump(const Duration(milliseconds: 500));
      expect(Hive.box('vendor_entries').length, count);
      await tester.ensureVisible(find.text('End'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('End'));
        await Future<void>.delayed(const Duration(milliseconds: 40));
      });
      await tester.pumpAndSettle();
      expect(find.text('Successfully completed ride'), findsOneWidget);
      expect(find.text(money(180)), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  for (final language in ['English', 'Tamil']) {
    testWidgets('$language reports work on a phone with enlarged text', (
      tester,
    ) async {
      await tester.runAsync(
        () => Hive.box('settings').put('languageMode', language),
      );
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(language == 'Tamil' ? 'ta' : 'en'),
          supportedLocales: const [Locale('en'), Locale('ta')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: const SellScreen(initialSection: 2),
        ),
      );
      await tester.pump(const Duration(milliseconds: 1000));
      expect(find.byType(ReportsScreen), findsOneWidget);
      expect(find.text('Sell'), findsNothing);
      expect(find.text('Stock'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  Future<void> mountApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      await Hive.box('settings').put('currentUser', 'Appa');
      await savePurpose('Ranch', defaultNavigation('Ranch'));
    });
    await tester.pumpWidget(const VimoApp());
    await tester.pump(const Duration(milliseconds: 800));
  }

  testWidgets('An edge swipe returns exactly one page instead of restarting', (
    tester,
  ) async {
    await mountApp(tester);
    await tester.tap(find.text('Reports'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Milk Collected'));
    await tester.pumpAndSettle();
    expect(find.byType(ReportDetailsScreen), findsOneWidget);
    await tester.dragFrom(const Offset(389, 360), const Offset(-130, 0));
    await tester.pumpAndSettle();
    expect(find.byType(ReportDetailsScreen), findsNothing);
    expect(find.byType(ReportsScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('The focused field stays above the keyboard after it opens', (
    tester,
  ) async {
    await mountApp(tester);
    final ctx = tester.element(find.byType(MainShell));
    push(ctx, const VendorPersonForm());
    await tester.pumpAndSettle();
    final field = find.byWidgetPredicate(
      (w) => w is TextFormField && w.controller?.text == '60',
    );
    await tester.scrollUntilVisible(
      field,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(field);
    await tester.pump();
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.getRect(field).bottom, lessThanOrEqualTo(524));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
