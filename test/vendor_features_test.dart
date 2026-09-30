import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:ranch_management/main.dart';

void main() {
  late Directory dir;
  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('vimo_features_');
    Hive.init(dir.path);
    for (final name in backupBoxNames) {
      await Hive.openBox(name);
    }
    await Hive.openBox(VendorRoutes.boxName);
  });
  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });
  setUp(() async {
    for (final name in [...backupBoxNames, VendorRoutes.boxName]) {
      await Hive.box(name).clear();
    }
    await Hive.box('settings').putAll({
      'languageMode': 'English',
      'currentRole': 'Admin',
      'deviceId': 'features-test',
      'defaultMilkPrice': 60,
    });
  });

  Map<String, dynamic> person(
    String id, {
    String place = 'Erode',
    String kind = 'customer',
  }) => {
    'id': id,
    'cloudId': id,
    'kind': kind,
    'name': id,
    'place': place,
    'contact': '9876543210',
    'imageData': 'data:image/jpeg;base64,AAAA',
    'quantity': 2.0,
    'price': 60.0,
    'days': <int>[],
    'sessions': ['Morning', 'Evening'],
    'paymentCycle': 'Daily',
    'paymentDays': [0, 1, 2, 3, 4, 5, 6],
    'paymentMonthDay': 1,
  };

  Map<String, dynamic> supply(double litres) => {
    'cloudId': 'supply',
    'kind': 'collection',
    'stockScope': 'vendor_v2',
    'quantity': litres,
    'amount': litres * 40,
    'paid': litres * 40,
    'personId': 'supplier',
    'date': todayDate(),
  };

  group('Place groups', () {
    test('Spellings of one place merge; the common spelling labels it', () {
      final groups = vendorPlaceGroups([
        person('A', place: 'Chennai'),
        person('B', place: ' chennai.'),
        person('C', place: 'Erode'),
        person('D', place: ''),
        person('E', place: 'CHENNAI'),
        person('F', place: 'Chennai'),
      ]);
      expect(groups.map((g) => g.label).toList(), [
        'Chennai',
        'Erode',
        'No place',
      ]);
      expect(groups.first.people.map((p) => p['id']).toList(), [
        'A',
        'B',
        'E',
        'F',
      ]);
      expect(vendorPlaceKey('  Tiru-Chengode '), 'tiru chengode');
    });

    test('Known places are suggested, most used first', () async {
      await Hive.box('vendor_people').putAll({
        'A': person('A', place: 'Erode'),
        'B': person('B', place: 'Salem'),
        'C': person('C', place: 'salem'),
      });
      expect(vendorKnownPlaces(), ['Salem', 'Erode']);
    });
  });

  group('Milk clearance', () {
    test('Clearance leaves stock, never changes a balance', () async {
      await Hive.box('vendor_people').put('Kumar', person('Kumar'));
      await Hive.box('vendor_entries').put('supply', supply(10));
      await VendorLedger.record(
        id: 'clear-fridge',
        person: vendorFridge,
        kind: 'clearance',
        quantity: 3,
      );
      await VendorLedger.record(
        id: 'clear-kumar',
        person: person('Kumar'),
        kind: 'clearance',
        quantity: 2,
      );
      final rows = vendorRows('vendor_entries');
      expect(vendorMilkBalance(rows), 5);
      expect(vendorPersonDue('Kumar', rows), 0);
      final fridge = rows.firstWhere((r) => r['cloudId'] == 'clear-fridge');
      expect(fridge['amount'], 0.0);
      expect(fridge['personKind'], 'fridge');
      expect(vendorEntryPersonName(fridge), 'Fridge');
      expect(vendorEntryLabel('clearance'), 'Milk clearance');
    });

    test('Clearance cannot exceed the milk in hand or carry a price', () async {
      await Hive.box('vendor_entries').put('supply', supply(2));
      await expectLater(
        VendorLedger.record(
          id: 'too-much',
          person: vendorFridge,
          kind: 'clearance',
          quantity: 5,
        ),
        throwsStateError,
      );
      await expectLater(
        VendorLedger.record(
          id: 'priced',
          person: vendorFridge,
          kind: 'clearance',
          quantity: 1,
          price: 10,
        ),
        throwsStateError,
      );
      expect(vendorMilkBalance(vendorRows('vendor_entries')), 2);
    });
  });

  group('Route maps', () {
    Map<String, dynamic> route() => {
      'id': 'route1',
      'kind': 'own',
      'scope': VendorRoutes.scope,
      'name': 'Morning round',
      'path': [
        [11.0, 78.0],
        [11.001, 78.001],
        [11.002, 78.002],
      ],
      'stops': [
        {'id': 'Kumar', 'name': 'Kumar', 'lat': 11.001, 'lng': 78.001},
        {'id': 'Ravi', 'name': 'Ravi', 'lat': 11.002, 'lng': 78.002},
      ],
      'notes': [
        {
          'id': 'n1',
          'stopId': 'Kumar',
          'lat': 11.001,
          'lng': 78.001,
          'text': 'Blue gate',
          'photo': '',
          'voice': 'x' * 950000,
          'voiceSeconds': 20,
        },
      ],
    };

    test('A lent route carries no contact, photo or history', () async {
      await Hive.box('vendor_people').putAll({
        'Kumar': person('Kumar'),
        'Ravi': person('Ravi', place: 'Salem'),
      });
      await Hive.box('vendor_entries').putAll({
        'supply': supply(10),
        'old': {
          'cloudId': 'old',
          'kind': 'sale',
          'stockScope': 'vendor_v2',
          'quantity': 1,
          'amount': 60,
          'paid': 0,
          'personId': 'Kumar',
          'date': todayDate(),
        },
      });
      final shown = RouteShareService.payload(route(), collectLater: false);
      final stop = (shown.route['stops'] as List).first as Map;
      expect(stop.keys.toSet(), {
        'id',
        'name',
        'place',
        'lat',
        'lng',
        'litres',
        'price',
        'due',
      });
      expect(stop['due'], 60.0);
      // Firestore has no nested arrays; the path travels as points.
      expect((shown.route['path'] as List).first, {'lat': 11.0, 'lng': 78.0});
      expect(routePath(shown.route).length, 3);
      expect(stop['litres'], 2.0);
      // Too large for one document: voice notes go, the text stays.
      expect(shown.trimmed, isTrue);
      final note = (shown.route['notes'] as List).first as Map;
      expect(note['voice'], '');
      expect(note['text'], 'Blue gate');

      final hidden = RouteShareService.payload(route(), collectLater: true);
      final hiddenStop = (hidden.route['stops'] as List).first as Map;
      expect(hiddenStop.containsKey('price'), isFalse);
      expect(hiddenStop.containsKey('due'), isFalse);
      expect(hiddenStop['litres'], 2.0);
    });

    test('Routes are stored per workspace and measured', () async {
      await VendorRoutes.save(route());
      final box = await VendorRoutes.open();
      expect(VendorRoutes.own(box).single['name'], 'Morning round');
      expect(routeStops(VendorRoutes.byId('route1')!).length, 2);
      expect(routePath(route()).length, 3);
      expect(routeDistanceMeters(routePath(route())), greaterThan(250));
      expect(routePoint(200, 10), isNull);
      await VendorRoutes.delete('route1');
      expect(VendorRoutes.own(box), isEmpty);
    });

    test('Time left reads naturally and ends at zero', () {
      final now = DateTime(2026, 9, 30, 8);
      expect(
        routeTimeLeft(now.add(const Duration(days: 2, hours: 3)), now: now),
        '2d 3h left',
      );
      expect(
        routeTimeLeft(now.add(const Duration(minutes: 90)), now: now),
        '1h 30m left',
      );
      expect(routeTimeLeft(now, now: now), 'Ended');
    });

    test('The chat card names the route but carries no customer data', () {
      final card = ShareCard.route(
        shareId: 's1',
        name: 'Morning round',
        owner: 'Owner',
        homes: 8,
      );
      final decoded = ShareCard.decode(card.encode());
      expect(decoded?.kind, 'route');
      expect(decoded?.data['s'], 's1');
      expect(decoded?.data.keys.toSet(), {'k', 's', 'n', 'o', 'c'});
    });
  });

  group('Ride', () {
    Future<void> mount(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: VendorRideScreen())),
      );
      await tester.pump(const Duration(milliseconds: 600));
    }

    testWidgets('Any customer can be completed first, not only the next', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await Hive.box(
          'vendor_people',
        ).putAll({'Anbu': person('Anbu'), 'Bala': person('Bala')});
        await Hive.box('vendor_entries').put('supply', supply(10));
      });
      await mount(tester);
      await tester.runAsync(() async {
        await tester.tap(find.text('Start'));
        await Future<void>.delayed(const Duration(milliseconds: 40));
      });
      await tester.pump(const Duration(milliseconds: 1900));
      expect(find.text('Swipe any customer, in any order'), findsOneWidget);
      final second = find
          .ancestor(of: find.text('Bala'), matching: find.byType(Glass))
          .first;
      await tester.runAsync(() async {
        await tester.drag(second, const Offset(160, 0));
        for (var i = 0; i < 60; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          if (vendorRows(
            'vendor_entries',
          ).any((r) => r['kind'] == 'sale' && r['personId'] == 'Bala')) {
            break;
          }
        }
      });
      for (var i = 0; i < 30 && find.text('Received').evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      final sales = vendorRows(
        'vendor_entries',
      ).where((r) => r['kind'] == 'sale').toList();
      expect(sales.map((r) => r['personId']).toList(), ['Bala']);
      expect(find.text('Received'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('Place bubbles lead the list and start one place', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await Hive.box('vendor_people').putAll({
          'Anbu': person('Anbu', place: 'Erode'),
          'Bala': person('Bala', place: 'Chennai'),
          'Chitra': person('Chitra', place: 'chennai'),
        });
        await Hive.box('settings').put('vendorRide__local_groups', true);
      });
      await mount(tester);
      expect(find.text('Chennai'), findsWidgets);
      expect(find.text('Erode'), findsWidgets);
      final bubble = find.descendant(
        of: find.byType(VendorPlaceBubbles),
        matching: find.text('Chennai'),
      );
      await tester.ensureVisible(bubble);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(bubble);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Start · Chennai'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text('Start · Chennai'));
        await Future<void>.delayed(const Duration(milliseconds: 40));
      });
      await tester.pump(const Duration(milliseconds: 1900));
      final saved = Hive.box('settings').get('vendorRide__local') as Map;
      expect(((saved['stops'] as List).map((s) => (s as Map)['id'])).toSet(), {
        'Bala',
        'Chitra',
      });
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('A customer monthly report adds up the month', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final month = thisMonth();
      await tester.runAsync(() async {
        await Hive.box('vendor_people').put('Kumar', person('Kumar'));
        await Hive.box('vendor_entries').putAll({
          'before': {
            'cloudId': 'before',
            'kind': 'sale',
            'quantity': 1,
            'amount': 60,
            'paid': 0,
            'personId': 'Kumar',
            'session': 'Morning',
            'date': '2000-01-05',
          },
          'm1': {
            'cloudId': 'm1',
            'kind': 'sale',
            'quantity': 2,
            'amount': 120,
            'paid': 120,
            'personId': 'Kumar',
            'session': 'Morning',
            'date': '$month-01',
          },
          'm2': {
            'cloudId': 'm2',
            'kind': 'sale',
            'quantity': 1.5,
            'amount': 90,
            'paid': 0,
            'personId': 'Kumar',
            'session': 'Evening',
            'date': '$month-01',
          },
        });
      });
      await tester.pumpWidget(
        MaterialApp(home: CustomerMonthlyReportScreen(person: person('Kumar'))),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('3.5 L'), findsOneWidget);
      expect(find.text(money(210)), findsWidgets);
      expect(find.text(money(60)), findsOneWidget);
      expect(find.text(money(150)), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
