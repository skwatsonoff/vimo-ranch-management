import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:ranch_management/main.dart';

void main() {
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('vimo_bugfix_');
    Hive.init(directory.path);
    for (final name in backupBoxNames) {
      await Hive.openBox(name);
    }
  });
  setUp(() async {
    AutoSyncService.stop();
    for (final name in backupBoxNames) {
      await Hive.box(name).clear();
    }
    await Hive.box('settings').putAll({
      'currentRole': 'Admin',
      'currentUser': 'Tester',
      'languageMode': 'English',
      'workspaceSyncEnabled': false,
    });
  });
  tearDownAll(() async {
    AutoSyncService.stop();
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('Calendar spans clamp month ends, leap days and future dates', () {
    expect(calendarSpan(DateTime(2026, 1, 31), DateTime(2026, 2, 28)), (
      years: 0,
      months: 1,
      days: 0,
    ));
    expect(calendarSpan(DateTime(2026, 1, 31), DateTime(2026, 3, 1)), (
      years: 0,
      months: 1,
      days: 1,
    ));
    expect(calendarSpan(DateTime(2024, 2, 29), DateTime(2025, 2, 28)), (
      years: 1,
      months: 0,
      days: 0,
    ));
    expect(calendarSpan(DateTime(2026, 12, 31), DateTime(2026, 1, 1)), (
      years: 0,
      months: 0,
      days: 0,
    ));
  });

  test('Tamil age/duration labels leave export ages in English', () async {
    final animal = {'ageYears': 2, 'ageMonths': 3};
    await Hive.box('settings').put('languageMode', 'Tamil');
    expect(ageTextLocal(animal), '2 ஆண்டு 3 மாதம்');
    expect(ageText(animal), '2 Years 3 Months');
    expect(durationText(todayDate()), 'இன்று');
    expect(durationText('invalid'), 'அமைக்கவில்லை');
    expect(monthLabel('invalid'), 'invalid');
  });

  test('Malformed nested social fields preserve valid fields and posts', () {
    final post = decodeSocialPost({
      'document': {
        'name': 'projects/demo/databases/(default)/documents/social_posts/one',
        'fields': {
          'text': {'stringValue': 'Still readable'},
          'bad': 12,
          'timestamp': {'timestampValue': 'invalid'},
          'integer': {'integerValue': 'invalid'},
          'nested': {
            'arrayValue': {
              'values': [
                null,
                {'integerValue': '7'},
              ],
            },
          },
          'map': {
            'mapValue': {
              'fields': {'broken': 'invalid'},
            },
          },
        },
      },
    });
    expect(post!.id, 'one');
    expect(post.data()['text'], 'Still readable');
    expect(post.data()['bad'], isNull);
    expect(post.data()['nested'], [null, 7]);
    expect(post.data()['map'], {'broken': null});
    expect(decodeSocialField({'doubleValue': 'NaN'}), isNull);
    expect(decodeSocialField({'arrayValue': 'bad'}), isEmpty);
    expect(
      decodeSocialPost({
        'document': {'name': 12},
      }),
      isNull,
    );
    expect(decodeSocialPost(null), isNull);
  });

  test(
    'Vendor weekday imports accept whole doubles and reject invalid days',
    () {
      expect(vendorWeekdays([0.0, 6, 6.0, -1, 7, 1.5, double.nan, '2']), {
        0,
        6,
      });
      expect(vendorWeekdays('invalid'), isEmpty);
      expect(vendorFieldNumber(90.44999999999999), '90.45');
      expect(vendorFieldNumber(1.0), '1');
    },
  );

  Future<void> mountAnimalPage(
    WidgetTester tester,
    Widget page, {
    String status = 'Active',
  }) async {
    await tester.runAsync(
      () => Hive.box(
        'animals',
      ).put('animal', {'name': 'Test cow', 'type': 'cow', 'status': status}),
    );
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    tester
        .state<NavigatorState>(find.byType(Navigator))
        .push(MaterialPageRoute<void>(builder: (_) => page));
    await tester.pumpAndSettle();
  }

  testWidgets('Rapid double save creates exactly one animal sale', (
    tester,
  ) async {
    await tester.runAsync(() => saveRanchCustomer(name: 'Buyer'));
    await mountAnimalPage(tester, const SellAnimalScreen(animalKey: 'animal'));
    tester
        .widget<DropdownButtonFormField<String>>(
          find.byType(DropdownButtonFormField<String>),
        )
        .onChanged!('Buyer');
    for (final field in tester.widgetList<TextField>(find.byType(TextField))) {
      if (field.decoration?.labelText == 'Sale Price / Income') {
        field.controller!.text = '100';
      }
    }
    final save = tester
        .widget<LiquidButton>(
          find.byWidgetPredicate(
            (widget) => widget is LiquidButton && widget.label == 'Save Sale',
          ),
        )
        .onPressed!;
    await tester.runAsync(() async {
      save();
      save();
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await tester.pumpAndSettle();
    expect(Hive.box('sale_records').length, 1);
    expect(Hive.box('animals').get('animal')['status'], 'Sold');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Already sold animal cannot create another sale', (tester) async {
    await mountAnimalPage(
      tester,
      const SellAnimalScreen(animalKey: 'animal'),
      status: 'Sold',
    );
    tester
        .widget<LiquidButton>(
          find.byWidgetPredicate(
            (widget) => widget is LiquidButton && widget.label == 'Save Sale',
          ),
        )
        .onPressed!();
    await tester.pump();
    expect(Hive.box('sale_records').isEmpty, true);
    expect(find.text('This animal is already sold'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Death confirmation cannot duplicate; cancel permits retry', (
    tester,
  ) async {
    await mountAnimalPage(tester, const DeathScreen(animalKey: 'animal'));
    final save =
        tester
                .widget<LiquidButton>(
                  find.byWidgetPredicate(
                    (widget) =>
                        widget is LiquidButton &&
                        widget.label == 'Save Death Record',
                  ),
                )
                .onPressed!
            as Future<void> Function();
    late Future<void> pending;
    await tester.runAsync(() async {
      pending = save();
      save();
    });
    // The saving spinner intentionally animates while confirmation is open.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(AppleAlert), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.runAsync(() => pending);
    await tester.pumpAndSettle();
    expect(Hive.box('death_records').isEmpty, true);
    await tester.runAsync(() async {
      pending = save();
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Confirm'));
    await tester.pump();
    await tester.runAsync(() => pending);
    await tester.pumpAndSettle();
    expect(Hive.box('death_records').length, 1);
    expect(Hive.box('animals').get('animal')['status'], 'Died');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
