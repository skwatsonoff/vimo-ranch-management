import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:ranch_management/main.dart';

void main() {
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('vimo_interface_');
    Hive.init(directory.path);
    for (final name in backupBoxNames) {
      await Hive.openBox(name);
    }
  });
  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  testWidgets(
    'Tamil task form stays usable on a narrow screen with large text',
    (tester) async {
      await tester.runAsync(
        () => Hive.box('settings').putAll({
          'languageMode': 'Tamil',
          'currentUser': 'அருண்',
          'currentRole': 'Admin',
        }),
      );
      tester.view.physicalSize = const Size(390, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ta'),
          supportedLocales: const [Locale('ta'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: const TaskComposerScreen(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
      expect(ui('New task'), 'புதிய வேலை');
      expect(find.text('முடிக்க வேண்டிய நேரம்'), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.ensureVisible(find.byType(FilledButton));
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(Hive.box('ranch_tasks').isEmpty, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test('language preference does not alter ranch permissions', () async {
    await Hive.box('settings').put('currentRole', 'Data Entry');
    await Hive.box('settings').put('languageMode', 'English');
    expect(isDataEntryUser, isTrue);
    expect(tamilUi, isFalse);
    await Hive.box('settings').put('languageMode', 'Tamil');
    expect(isDataEntryUser, isTrue);
    expect(ui('Tasks'), 'வேலைகள்');
  });

  testWidgets('daily entry form hides automatic date and time fields', (
    tester,
  ) async {
    await tester.runAsync(
      () => Hive.box('settings').putAll({
        'languageMode': 'English',
        'currentUser': 'Appa',
        'currentRole': 'Admin',
      }),
    );
    await tester.pumpWidget(const MaterialApp(home: AddEntryScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byType(DateField), findsNothing);
    expect(find.text('Date'), findsNothing);
    expect(find.text('Time'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('recent activity keeps its record target for menu actions', () async {
    await Hive.box('settings').putAll({
      'currentUser': 'Appa',
      'currentRole': 'Admin',
      'deviceId': 'test-device',
    });
    await Hive.box('milk_records').clear();
    final key = await Hive.box('milk_records').add({
      'cow': 'Mala',
      'quantity': 4.5,
      'date': todayDate(),
      'time': currentTime(),
      'addedBy': 'Appa',
      'createdAt': DateTime.now().toIso8601String(),
    });

    final activity = recentActivities(limit: 1).single;
    expect(activity['_box'], 'milk_records');
    expect(activity['_key'], key);
    expect(canCorrectEntry(asMap(Hive.box('milk_records').get(key))), isTrue);
  });

  test('ranch details never leaves a standalone separator', () async {
    await Hive.box('settings').putAll({'ownerName': '', 'place': ''});
    expect(ranchDetails(), isEmpty);
    await Hive.box('settings').putAll({'ownerName': 'Kumar', 'place': ''});
    expect(ranchDetails(), 'Kumar');
    await Hive.box('settings').put('place', 'Erode');
    expect(ranchDetails(), 'Kumar • Erode');
  });
}
