import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:ranch_management/main.dart';

void main() {
  late Directory dir;
  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('vimo_shop_');
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
      'deviceId': 'shop-test',
      'defaultMilkPrice': 60,
      'purposeProfiles': {
        'local': {
          'purpose': 'Vendor',
          'order': ['Vendor', 'Reports', 'Social', 'Chat'],
          'workspaces': ['Vendor'],
          'vendorMode': 'shop',
        },
      },
    });
  });

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

  Map<String, dynamic> item(String id) =>
      shopItems().firstWhere((m) => m['id'] == id);

  group('Vendor mode', () {
    test('Milk shop is chosen per account and kept by later saves', () async {
      expect(vendorMode, 'shop');
      expect(milkShopMode, isTrue);
      expect(navLabel('Vendor'), 'Milk shop');
      await savePurpose('Vendor', ['Vendor', 'Reports', 'Social', 'Chat']);
      expect(vendorMode, 'shop');
      await saveVendorMode('vendor');
      expect(milkShopMode, isFalse);
      expect(navLabel('Vendor'), 'Vendor');
      expect(() => saveVendorMode('market'), throwsArgumentError);
    });
  });

  group('Keypad', () {
    test('Digits, half and quarter build the quantity', () {
      var q = const ShopQuantity().digit(1);
      expect(q.value, 1);
      q = q.toggleHalf();
      expect((q.value, q.label), (1.5, '1.5'));
      q = q.toggleQuarter();
      expect((q.value, q.label), (1.75, '1.75'));
      q = q.digit(2);
      expect((q.value, q.label), (12.75, '12.75'));
      q = q.backspace().backspace();
      expect(q.label, '12');
      expect(const ShopQuantity().toggleQuarter().label, '0.25');
      expect(const ShopQuantity(whole: 9999).digit(9).whole, 9999);
    });
  });

  group('Catalog', () {
    test('Milk, Curd and Ghee are the main buttons by default', () {
      expect(shopItems().map((m) => m['id']).toList(), [
        'milk',
        'curd',
        'ghee',
      ]);
      expect(shopQuickIds(), ['milk', 'curd', 'ghee']);
      // Milk falls back to the default milk rate until a shop price is set.
      expect(shopPrice(item('milk')), 60);
      expect(shopPrice(item('curd')), 0);
    });

    test('Added items join Others and can take a main place', () async {
      final items = shopItems()
        ..add({'id': 'item_1', 'name': 'Paneer', 'unit': 'kg', 'price': 400.0});
      await saveShopCatalog(items, ['milk', 'item_1', 'ghee']);
      expect(shopQuickIds(), ['milk', 'item_1', 'ghee']);
      final remaining = shopItems()..removeWhere((m) => m['id'] == 'item_1');
      expect(shopQuickIdsAfter(remaining, ['milk', 'ghee']), [
        'milk',
        'ghee',
        'curd',
      ]);
    });
  });

  group('Ledger', () {
    test('Shop milk sales come out of the milk from providers', () async {
      await Hive.box('vendor_entries').put('supply', supply(10));
      expect(shopAvailable('milk'), 10);
      await ShopLedger.record(
        id: 'sale-1',
        kind: 'sale',
        item: item('milk'),
        quantity: 1.5,
        price: 60,
      );
      final sale = asMap(Hive.box(shopBox).get('sale-1'));
      expect(sale['amount'], 90.0);
      expect(sale['pendingUpload'], isTrue);
      expect(shopAvailable('milk'), 8.5);
      expect(vendorMilkOnHand(), 8.5);
      // A retry with the same id never sells twice.
      await ShopLedger.record(
        id: 'sale-1',
        kind: 'sale',
        item: item('milk'),
        quantity: 1.5,
        price: 60,
      );
      expect(shopAvailable('milk'), 8.5);
    });

    test('Sales stop at the stock; stock additions raise it', () async {
      await expectLater(
        ShopLedger.record(
          id: 'curd-1',
          kind: 'sale',
          item: {...item('curd'), 'price': 50.0},
          quantity: 1,
          price: 50,
        ),
        throwsA(isA<ShopStockShortage>()),
      );
      await ShopLedger.record(
        id: 'curd-stock',
        kind: 'stock',
        item: item('curd'),
        quantity: 4,
      );
      await ShopLedger.record(
        id: 'curd-2',
        kind: 'sale',
        item: item('curd'),
        quantity: .75,
        price: 50,
      );
      expect(shopAvailable('curd'), 3.25);
    });

    test('Bad entries are refused', () async {
      await ShopLedger.record(
        id: 'stock',
        kind: 'stock',
        item: item('ghee'),
        quantity: 2,
      );
      for (final (quantity, price) in [(0.0, 50.0), (1.0, 0.0), (-1.0, 9.0)]) {
        await expectLater(
          ShopLedger.record(
            id: 'bad',
            kind: 'sale',
            item: item('ghee'),
            quantity: quantity,
            price: price,
          ),
          throwsStateError,
        );
      }
      await expectLater(
        ShopLedger.record(
          id: 'half-biscuit',
          kind: 'stock',
          item: {'id': 'item_2', 'name': 'Biscuit', 'unit': 'count'},
          quantity: 1.5,
        ),
        throwsStateError,
      );
    });

    test('A cancelled sale stays listed and returns the stock', () async {
      await Hive.box('vendor_entries').put('supply', supply(5));
      await ShopLedger.record(
        id: 'sale-2',
        kind: 'sale',
        item: item('milk'),
        quantity: 2,
        price: 60,
      );
      final row = shopRows().single;
      expect(ShopLedger.canVoid(row), isTrue);
      await ShopLedger.voidSale(row);
      final cancelled = asMap(Hive.box(shopBox).get('sale-2'));
      expect(cancelled['voided'], isTrue);
      expect(cancelled['pendingUpload'], isTrue);
      expect(shopAvailable('milk'), 5);
      expect(ShopLedger.canVoid(shopRows().single), isFalse);
    });

    test('Vendor sales also see what the shop sold', () async {
      await Hive.box('vendor_entries').put('supply', supply(3));
      await ShopLedger.record(
        id: 'sale-3',
        kind: 'sale',
        item: item('milk'),
        quantity: 2,
        price: 60,
      );
      await expectLater(
        VendorLedger.record(
          id: 'clear',
          person: vendorFridge,
          kind: 'clearance',
          quantity: 2,
        ),
        throwsStateError,
      );
    });
  });

  testWidgets('Milk keypad and slide to sell record a counter sale', (
    tester,
  ) async {
    await tester.runAsync(
      () => Hive.box('vendor_entries').put('supply', supply(10)),
    );
    await tester.binding.setSurfaceSize(const Size(390, 1100));
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: MilkShopScreen())),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Milk'), findsWidgets);
    expect(find.text('Others'), findsOneWidget);
    expect(find.textContaining('10 L', findRichText: true), findsOneWidget);

    await tester.tap(
      find
          .ancestor(
            of: find.text('Milk').last,
            matching: find.byType(Pressable),
          )
          .first,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    // Before any litres the fraction keys are plain.
    expect(find.text('.500'), findsOneWidget);
    await tester.tap(find.text('1'));
    await tester.pump();
    // With litres entered both keys offer to add: "+.500" and "+.250".
    expect(find.text('+.500'), findsOneWidget);
    expect(find.text('+.250'), findsOneWidget);
    await tester.tap(find.text('+.500'));
    await tester.pump();
    expect(find.textContaining('1.5', findRichText: true), findsOneWidget);
    expect(find.textContaining('₹90', findRichText: true), findsWidgets);

    final slider = find.byType(SlideToSell);
    final start = tester.getTopLeft(slider) + const Offset(32, 32);
    await tester.runAsync(() async {
      await tester.dragFrom(start, const Offset(400, 0));
      await Future<void>.delayed(const Duration(milliseconds: 60));
    });
    await tester.pump(const Duration(milliseconds: 600));
    final sale = shopRows().single;
    expect(sale['quantity'], 1.5);
    expect(sale['amount'], 90.0);
    // Selling keeps only the sale on screen; closing it shows the stock.
    expect(find.byType(VendorProvidersStrip), findsNothing);
    await tester.tap(
      find
          .ancestor(
            of: find.text('Milk').first,
            matching: find.byType(Pressable),
          )
          .first,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(VendorProvidersStrip), findsOneWidget);
    expect(find.textContaining('8.5 L', findRichText: true), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
  });
}
