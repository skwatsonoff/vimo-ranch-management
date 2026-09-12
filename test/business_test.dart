import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:ranch_management/main.dart';

void main() {
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('vimo_business_');
    Hive.init(directory.path);
    for (final name in backupBoxNames) {
      await Hive.openBox(name);
    }
  });
  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });
  setUp(() async {
    await Hive.box('settings').putAll({
      'currentUser': 'Tester',
      'currentRole': 'Admin',
      'languageMode': 'English',
      'purposeProfiles': {},
    });
    await Hive.box('vendor_people').clear();
    await Hive.box('vendor_entries').clear();
  });
  test(
    'purpose defaults and custom order preserve all five destinations',
    () async {
      expect(purposeChosen, false);
      await savePurpose('Vendor', defaultNavigation('Vendor'));
      expect(navigationOrder().first, 'Vendor');
      expect(purposeChosen, true);
      await savePurpose('Market', [
        'Social',
        'Chat',
        'Sell',
        'Vendor',
        'Ranch',
      ]);
      expect(navigationOrder(), ['Social', 'Chat', 'Sell', 'Vendor', 'Ranch']);
      await expectLater(savePurpose('Ranch', ['Ranch']), throwsArgumentError);
      expect(navigationOrder().first, 'Social');
      expect(defaultNavigation('Market').first, 'Sell');
    },
  );
  test(
    'repeated supplier purchases and deliveries calculate separate stock and credit',
    () {
      final entries = <Map<String, dynamic>>[
        {
          'kind': 'purchase',
          'personId': 's1',
          'quantity': 10.0,
          'amount': 400.0,
          'paid': 100.0,
        },
        {
          'kind': 'purchase',
          'personId': 's1',
          'quantity': 5.0,
          'amount': 200.0,
          'paid': 200.0,
        },
        {
          'kind': 'purchase',
          'personId': 's2',
          'quantity': 8.0,
          'amount': 320.0,
          'paid': 0.0,
        },
        {
          'kind': 'sale',
          'personId': 'c1',
          'quantity': 3.0,
          'amount': 180.0,
          'paid': 30.0,
        },
        {'kind': 'payment', 'personId': 'c1', 'amount': 100.0},
      ];
      expect(vendorMilkBalance(entries), 20);
      expect(vendorPersonDue('s1', entries), 300);
      expect(vendorPersonDue('s2', entries), 320);
      expect(vendorPersonDue('c1', entries), 50);
    },
  );
  test(
    'delivery schedules distinguish Sunday and Saturday and both sessions',
    () {
      final person = <String, dynamic>{
        'kind': 'customer',
        'days': [0, 6],
        'sessions': ['Morning', 'Evening'],
      };
      expect(vendorDeliveryDue(person, DateTime(2026, 9, 13), 'Morning'), true);
      expect(vendorDeliveryDue(person, DateTime(2026, 9, 12), 'Evening'), true);
      expect(
        vendorDeliveryDue(person, DateTime(2026, 9, 14), 'Morning'),
        false,
      );
      expect(
        vendorDeliveryDue(
          {
            ...person,
            'sessions': ['Morning'],
          },
          DateTime(2026, 9, 13),
          'Evening',
        ),
        false,
      );
    },
  );
  test('malformed social media cannot throw while building the feed', () {
    expect(socialPhotoBytes('%%%'), isEmpty);
    expect(socialPhotoBytes('data:image/jpeg;base64,AQID'), [1, 2, 3]);
  });

  testWidgets('Vendor purpose routes Sell and Stock to vendor records', (
    tester,
  ) async {
    await tester.runAsync(
      () => savePurpose('Vendor', defaultNavigation('Vendor')),
    );
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: MainShell()));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('Sell'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.widget<VendorScreen>(find.byType(VendorScreen)).initialSection, 1);
    await tester.tap(find.text('Stock'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Vendor milk stock'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final language in ['English', 'Tamil']) {
    testWidgets(
      '$language vendor customer form works on narrow screens with large text',
      (tester) async {
        await tester.runAsync(
          () => Hive.box('settings').put('languageMode', language),
        );
        tester.view.physicalSize = const Size(390, 844);
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
              ).copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child!,
            ),
            home: const VendorPersonForm(kind: 'customer'),
          ),
        );
        await tester.pump(const Duration(milliseconds: 600));
        expect(tester.takeException(), isNull);
        expect(
          find.byType(FilterChip).evaluate().length,
          greaterThanOrEqualTo(7),
        );
        await tester.enterText(
          find.byType(TextFormField).at(0),
          language == 'Tamil' ? 'குமார்' : 'Kumar',
        );
        await tester.enterText(find.byType(TextFormField).at(1), 'Erode');
        await tester.drag(find.byType(ListView), const Offset(0, -450));
        await tester.pump(const Duration(milliseconds: 600));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  testWidgets(
    'vendor dashboard and first-run purpose selection render without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: VendorScreen())),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Your milk business'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        const MaterialApp(home: PreferencesScreen(onboarding: true)),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('What will you use VIMO for?'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
