import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:ranch_management/main.dart';

void main() {
  late Directory dir;
  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('vimo_roles_nav_');
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
      'deviceId': 'roles-test',
      'purposeProfiles': {},
    });
  });

  Widget app(Widget home) => MaterialApp(
    supportedLocales: const [Locale('en'), Locale('ta')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: home,
  );

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  test('Market uses Social, Reports, Chat and Profile', () async {
    expect(defaultNavigation('Market'), [
      'Social',
      'Reports',
      'Chat',
      'Profile',
    ]);
    await savePurpose('Market', defaultNavigation('Market'));
    expect(navigationOrder(), ['Social', 'Reports', 'Chat', 'Profile']);
    expect(enabledWorkspaces, ['Market']);
  });

  test('Every enabled workspace offers its tabs; the bar keeps four', () async {
    final all = ['Ranch', 'Vendor', 'Market'];
    expect(availableTabs(all), [
      'Ranch',
      'Vendor',
      'Reports',
      'Social',
      'Chat',
      'Profile',
    ]);
    final order = defaultNavigation('Ranch', workspaces: all);
    expect(order.length, navigationSlots);
    expect(order.first, 'Ranch');
    expect(order, contains('Vendor'));
    await savePurpose('Ranch', [
      'Vendor',
      'Profile',
      'Ranch',
      'Reports',
    ], workspaces: all);
    expect(navigationOrder(), ['Vendor', 'Profile', 'Ranch', 'Reports']);
    // A tab from a workspace that is off can never be saved.
    await expectLater(
      savePurpose('Ranch', ['Ranch', 'Vendor', 'Social', 'Chat']),
      throwsArgumentError,
    );
    // Switching a workspace off falls back to a valid layout.
    await Hive.box('settings').put('purposeProfiles', {
      'local': {
        'purpose': 'Ranch',
        'workspaces': ['Ranch'],
        'order': ['Vendor', 'Profile', 'Ranch', 'Reports'],
      },
    });
    expect(navigationOrder(), ['Ranch', 'Social', 'Chat', 'Profile']);
  });

  test('A bull never joins milk, mother or ranking lists', () async {
    final box = Hive.box('animals');
    await box.add({
      'type': 'cow',
      'name': 'Lakshmi',
      'gender': 'Female',
      'status': 'Active',
    });
    await box.add({
      'type': 'cow',
      'name': 'Maruthu',
      'gender': 'Male',
      'maleUse': 'Cart',
      'status': 'Active',
    });
    expect(cowNames(), ['Lakshmi']);
    expect(motherNames(), ['Unknown Mother', 'Lakshmi']);
    final bull = animals().firstWhere((a) => a['name'] == 'Maruthu');
    expect(isMaleAnimal(bull), isTrue);
    expect(maleUseOf(bull), 'Cart');
  });

  test('Cart work, jallikattu wins and breeding success are measured', () {
    final month = thisMonth();
    final cart = {
      'gender': 'Male',
      'maleUse': 'Cart',
      'workLog': [
        {'kind': 'work', 'date': '$month-02', 'hours': 3, 'earnings': 500},
        {'kind': 'work', 'date': '$month-02', 'hours': 2, 'earnings': 300},
        {'kind': 'work', 'date': '$month-05', 'hours': 4, 'earnings': 0},
      ],
    };
    final metrics = maleMetrics(cart);
    expect(metrics[0].$2, '2 days');
    expect(metrics[1].$2, '9 h');
    expect(metrics[2].$2, money(800));

    final jalli = {
      'gender': 'Male',
      'maleUse': 'Jallikattu',
      'workLog': [
        {'kind': 'event', 'date': '$month-01', 'result': 'Won', 'prize': 5000},
        {'kind': 'event', 'date': '$month-03', 'result': 'Tamed'},
        {'kind': 'training', 'date': '$month-04', 'minutes': 45},
      ],
    };
    final j = maleMetrics(jalli);
    expect(j[1].$2, '1 / 2');
    expect(j[2].$2, money(5000));

    final breeding = {
      'gender': 'Male',
      'maleUse': 'Breeding',
      'workLog': [
        {
          'kind': 'service',
          'date': '$month-01',
          'result': 'Confirmed',
          'fee': 700,
        },
        {'kind': 'service', 'date': '$month-02', 'result': 'Repeat'},
        {'kind': 'service', 'date': '$month-03', 'result': 'Pending'},
      ],
    };
    final b = maleMetrics(breeding);
    expect(b[1].$2, '50%');
    expect(b[2].$2, '1 / 3');
  });

  test('Shared cards survive the chat text round trip', () {
    final card = ShareCard.animal({
      'id': 'C004',
      'type': 'cow',
      'name': 'Lakshmi',
      'breed': 'Kangeyam',
      'gender': 'Female',
      'ageYears': 4,
    });
    final text = card.encode();
    expect(text.length, lessThan(2000));
    expect(text.split('\n').first, contains('Lakshmi'));
    final back = ShareCard.decode(text)!;
    expect(back.kind, 'animal');
    expect(back.displayName, 'Lakshmi');
    expect(back.ageLabel, '4 Years');
    expect(ShareCard.decode('hello'), isNull);
    expect(ShareCard.decode('x\n⁣vimo:not-base64!'), isNull);
  });

  test('Tamil mode translates interface text and keeps names', () async {
    await Hive.box('settings').put('languageMode', 'Tamil');
    expect(ui('Unknown breed'), 'இனம் தெரியாது');
    expect(ui('Please enter a valid email'), 'சரியான இமெயிலை எழுதவும்');
    expect(ui('Kangeyam'), 'காங்கேயம்');
    expect(navLabel('Chat'), 'சாட்');
    await Hive.box('settings').put('languageMode', 'English');
    expect(ui('காங்கேயம்'), 'Kangeyam');
  });

  testWidgets('Add animal: one name, photo first, no URL, bull purpose', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(app(const AddAnimalScreen(type: 'cow')));
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('Photo URL (optional)'), findsNothing);
    expect(find.text('Name in English'), findsNothing);
    expect(find.text('Name in Tamil'), findsNothing);
    expect(find.text('Cow name'), findsOneWidget);
    expect(find.text('Unknown'), findsWidgets);
    expect(find.text('What do you use this bull for?'), findsNothing);
    await tester.tap(find.text('Bull · Male'));
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('What do you use this bull for?'), findsOneWidget);
    expect(find.text('Jallikattu'), findsOneWidget);
    expect(find.text('Bull name'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Pregnant cows page uses the full width', (tester) async {
    phone(tester);
    await tester.pumpWidget(app(const PregnantCowsScreen()));
    await tester.pump(const Duration(milliseconds: 700));
    final note = tester.getSize(find.byType(EmptyNote));
    expect(note.width, greaterThan(300));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Preferences shows workspace switches and more tabs', (
    tester,
  ) async {
    phone(tester);
    await tester.runAsync(
      () => savePurpose('Vendor', defaultNavigation('Vendor')),
    );
    await tester.pumpWidget(app(const PreferencesScreen()));
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('Market'), findsOneWidget);
    expect(find.byType(CupertinoSwitch), findsNWidgets(3));
    expect(find.text('TAB ORDER'), findsOneWidget);
    // Vendor alone offers exactly its four tabs, so nothing is left over.
    expect(find.text('MORE TABS'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
