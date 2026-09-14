import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:ranch_management/main.dart';

void main() {
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('vimo_current_');
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
    for (final name in backupBoxNames) {
      await Hive.box(name).clear();
    }
    await Hive.box(
      'settings',
    ).putAll({'languageMode': 'English', 'currentRole': 'Admin'});
  });
  test(
    'English and Tamil stock and own-use labels preserve stored identities',
    () async {
      expect(ui('Vaikol'), 'Straw');
      expect(ui('Thavudu'), 'Bran');
      expect(ownUseDisplayName, 'Own use');
      expect(isOwnUseCustomer('Own use'), true);
      expect(isOwnUseCustomer('சொந்த பயன்பாடு'), true);
      await Hive.box('settings').put('languageMode', 'Tamil');
      expect(ui('Vaikol'), 'வைக்கோல்');
      expect(ui('Thavudu'), 'தவிடு');
      expect(ownUseDisplayName, 'சொந்த பயன்பாடு');
    },
  );
  test('Timeline combines only selected cow and calendar month', () {
    final result = monthlyCowMilk([
      {'cow': 'A', 'date': '2026-04-01', 'quantity': 30},
      {'cow': 'A', 'date': '2026-04-30', 'quantity': 50},
      {'cow': 'A', 'date': '2025-04-01', 'quantity': 5},
      {'cow': 'B', 'date': '2026-04-01', 'quantity': 90},
    ], 'A');
    expect(result, [
      {'date': '2026-04-01', 'quantity': 80.0},
      {'date': '2025-04-01', 'quantity': 5.0},
    ]);
    expect(monthLabel('2026-04-01'), 'April 2026');
  });
  test('Ranch report details exclude vendor sales and filter period', () async {
    await Hive.box('sale_records').addAll([
      {
        'type': 'Milk',
        'customerName': 'Kumar',
        'date': todayDate(),
        'time': '08:30',
        'quantity': 4,
        'amount': 200,
      },
      {
        'category': 'Milk Sale',
        'customerName': 'Older',
        'date': '2000-01-01',
        'quantity': 10,
        'amount': 500,
      },
      {
        'type': 'Milk',
        'customerName': 'சொந்த பயன்பாடு',
        'date': todayDate(),
        'quantity': 1,
        'amount': 0,
      },
    ]);
    await Hive.box('vendor_entries').add({
      'kind': 'sale',
      'personName': 'Store',
      'date': todayDate(),
      'quantity': 2,
      'amount': 100,
    });
    final sold = reportDetailRows('sold', 'Today');
    expect(sold.length, 1);
    expect(sold.map(reportRecordName), equals(['Kumar']));
    expect(sold.fold(0.0, (sum, r) => sum + numv(r, '_value')), 4);
    expect(
      reportDetailRows(
        'income',
        'Today',
      ).fold(0.0, (sum, r) => sum + numv(r, '_value')),
      200,
    );
  });
  test(
    'All expense sources and collected totals reconcile with detail rows',
    () async {
      for (final item in [
        ('food_records', 'price', 10),
        ('stock_records', 'amount', 20),
        ('expense_records', 'amount', 30),
        ('doctor_records', 'cost', 40),
        ('purchase_records', 'amount', 50),
        ('death_records', 'cost', 60),
      ]) {
        await Hive.box(
          item.$1,
        ).add({'date': todayDate(), item.$2: item.$3, 'movement': 'Purchase'});
      }
      expect(
        reportDetailRows(
          'expense',
          'Today',
        ).fold(0.0, (s, r) => s + numv(r, '_value')),
        totalExpense('Today'),
      );
      await Hive.box(
        'milk_records',
      ).add({'cow': 'A', 'date': todayDate(), 'quantity': 8});
      expect(
        reportDetailRows('collected', 'Today').single['_value'],
        milkTotal('Today'),
      );
    },
  );
  test('Profile links are optional and cannot execute script', () {
    expect(validProfileLink(''), true);
    expect(validProfileLink('https://example.com/a'), true);
    expect(validProfileLink('javascript:alert(1)'), false);
    expect(validProfileLink('https://user:password@example.com'), false);
  });
  testWidgets('Report detail shows customer, time and amount', (tester) async {
    await tester.runAsync(
      () => Hive.box('sale_records').add({
        'type': 'Milk',
        'customerName': 'Kumar',
        'date': todayDate(),
        'time': '08:30',
        'quantity': 4,
        'amount': 200,
      }),
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: ReportDetailsScreen(kind: 'sold', period: 'Today'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Kumar'), findsOneWidget);
    expect(find.textContaining('08:30'), findsOneWidget);
    expect(find.text('4.0 L'), findsOneWidget);
  });
  testWidgets('Composer never infers a username and explains the switch', (
    tester,
  ) async {
    await tester.runAsync(
      () => Hive.box('settings').put('currentUser', 'Unchosen Name'),
    );
    await tester.pumpWidget(const MaterialApp(home: SocialComposer()));
    await tester.pump();
    expect(find.text('@Unchosen Name'), findsNothing);
    expect(find.text('Colored text background'), findsOneWidget);
    expect(find.text('Choose a username'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
