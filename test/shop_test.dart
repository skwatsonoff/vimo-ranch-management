import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' hide Ink;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:ranch_management/main.dart';

/// Shop products and Mercari-style checkout: helpers, the listing form and
/// the purchase confirmation.
void main() {
  late Directory dir;
  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('vimo_shop_');
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
    await Hive.box('settings').clear();
    await Hive.box(
      'settings',
    ).putAll({'languageMode': 'English', 'currentUser': 'Appa'});
  });

  Widget app(Widget home) => MaterialApp(
    supportedLocales: const [Locale('en'), Locale('ta')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: home,
  );

  final product = <String, dynamic>{
    'sellerUid': 'seller',
    'sellerName': 'Selvi',
    'title': 'A2 Ghee 500 ml',
    'category': 'ghee',
    'condition': 'new',
    'price': 450.0,
    'mrp': 500.0,
    'unit': 'pack',
    'unitSize': '500 ml',
    'stock': 3,
    'maxPerOrder': 3,
    'delivery': {
      'methods': ['pickup', 'courier'],
      'payer': 'buyer',
      'fee': 40.0,
      'days': '2-3',
      'shipsFrom': 'Salem',
    },
    'returns': 'none',
    'cover': '',
    'photoCount': 1,
    'status': 'active',
  };

  group('helpers', () {
    test('search terms come from title, tags, brand and category', () {
      final terms = shopSearchTerms(
        title: 'Desi A2 Ghee, 500ml!',
        tags: ['Organic', 'cow ghee'],
        brand: 'Selvi Farm',
        category: 'ghee',
      );
      expect(
        terms,
        containsAll([
          'desi',
          'a2',
          'ghee',
          '500ml',
          'organic',
          'cow',
          'selvi',
          'farm',
          'butter',
        ]),
      );
      expect(terms.every((t) => t == t.toLowerCase()), isTrue);
      expect(terms.length, lessThanOrEqualTo(60));
    });

    test('tags are short, trimmed and lower case', () {
      expect(shopTag('  Pure   A2 Milk '), 'pure a2 milk');
      expect(shopTag('x' * 40).length, 24);
    });

    test('discount and delivery fee follow the listing', () {
      expect(shopDiscount(450, 500), 10);
      expect(shopDiscount(500, 0), 0);
      expect(shopDiscount(500, 450), 0);
      expect(shopDeliveryFee(product, 'courier'), 40);
      expect(shopDeliveryFee(product, 'pickup'), 0);
      final free = {
        ...product,
        'delivery': {...product['delivery'] as Map, 'payer': 'seller'},
      };
      expect(shopDeliveryFee(free, 'courier'), 0);
      expect(shopDeliverySummary(free), 'Free delivery');
      expect(shopDeliverySummary(product), '₹40 delivery');
    });

    test('cancelling is asked for, once, and only before it is sent', () {
      expect(ShopService.canAskCancel({'status': 'ordered'}), isTrue);
      expect(ShopService.canAskCancel({'status': 'accepted'}), isTrue);
      expect(ShopService.canAskCancel({'status': 'shipped'}), isFalse);
      expect(
        ShopService.canAskCancel({
          'status': 'ordered',
          'cancelRequest': {'by': 'buyer', 'reason': 'x'},
        }),
        isFalse,
      );
      expect(
        SocialActivityService.orderNoticeState({
          'status': 'accepted',
          'cancelRequest': {'by': 'seller', 'reason': 'Sold out'},
        }),
        'accepted:seller',
      );
      expect(
        SocialActivityService.orderNoticeState({'status': 'accepted'}),
        'accepted',
      );
    });

    test('only an accepted, cancelled order goes back on sale, once', () {
      expect(
        ShopService.canRestock({'status': 'cancelled', 'acceptedAt': 1}),
        isTrue,
      );
      expect(ShopService.canRestock({'status': 'cancelled'}), isFalse);
      expect(
        ShopService.canRestock({
          'status': 'cancelled',
          'acceptedAt': 1,
          'restocked': true,
        }),
        isFalse,
      );
    });

    test('order statuses read in plain words', () {
      expect(shopOrderStatusLabel('shipped'), 'On the way');
      expect(shopOrderStatusLabel('cancelled'), 'Cancelled');
    });
  });

  testWidgets('Listing form asks for a photo before anything else', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app(const ProductEditorScreen()));
    await tester.pumpAndSettle();
    expect(find.text('List a product'), findsOneWidget);
    expect(find.text('0/5'), findsOneWidget);
    expect(find.text('Search tags'), findsOneWidget);
    expect(find.text('More details'), findsOneWidget);
    await tester.tap(find.text('List product'));
    await tester.pump();
    expect(find.text('Add at least one photo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Tags stop at five and are lower case', (tester) async {
    tester.view.physicalSize = const Size(390, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app(const ProductEditorScreen()));
    await tester.pumpAndSettle();
    final tagField = find.widgetWithText(TextField, 'Add a tag');
    for (final t in ['A2', 'Organic', 'desi', 'cow', 'fresh']) {
      await tester.enterText(tagField, t);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
    }
    expect(find.byType(InputChip), findsNWidgets(5));
    expect(find.text('a2'), findsOneWidget);
    // At five the field goes away.
    expect(find.widgetWithText(TextField, 'Add a tag'), findsNothing);
  });

  testWidgets('A report needs a reason and a few words first', (tester) async {
    tester.view.physicalSize = const Size(390, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      app(
        const ReportProblemScreen(
          againstUid: 'seller',
          againstName: 'Selvi',
          topic: 'order',
          orderId: 'o1',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Item not received'), findsOneWidget);
    expect(find.textContaining('Only the VIMO Team sees this'), findsOneWidget);
    await tester.tap(find.text('Send to VIMO Team'));
    await tester.pump();
    expect(find.text('Choose what happened'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.tap(find.text('Item not received'));
    await tester.enterText(find.byType(TextField), 'late');
    await tester.tap(find.text('Send to VIMO Team'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.textContaining('at least 10 letters'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('One-per-order items have no quantity to choose', (tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      app(
        CheckoutScreen(
          id: 'cow',
          product: {
            ...product,
            'title': 'Jersey cow, 3 years',
            'category': 'animals',
            'maxPerOrder': 1,
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Quantity'), findsNothing);
    expect(find.byIcon(CupertinoIcons.plus), findsNothing);
    expect(find.text('Place order · ₹450'), findsOneWidget);
  });

  testWidgets('Checkout shows the total and asks for an address to deliver', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app(CheckoutScreen(id: 'p1', product: product)));
    await tester.pumpAndSettle();
    expect(find.text('Confirm purchase'), findsOneWidget);
    // Pickup first: no address, no fee.
    expect(find.text('Delivery address'), findsNothing);
    expect(find.text('Place order · ₹450'), findsOneWidget);
    // Two more, then courier with the buyer paying delivery.
    await tester.tap(find.byIcon(CupertinoIcons.plus));
    await tester.pump();
    await tester.tap(find.text('Courier / post'));
    await tester.pumpAndSettle();
    expect(find.text('Delivery address'), findsOneWidget);
    expect(find.text('Place order · ₹940'), findsOneWidget);
    // Quantity cannot pass the stock (3).
    await tester.tap(find.byIcon(CupertinoIcons.plus));
    await tester.pump();
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, CupertinoIcons.plus),
          )
          .onPressed,
      isNull,
    );
    // Address is checked before anything is sent.
    expect(find.text('Place order · ₹1390'), findsOneWidget);
    await tester.tap(find.text('Place order · ₹1390'));
    await tester.pump();
    expect(find.textContaining('Enter'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
