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
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(ui('New task'), 'புதிய பணி');
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
    expect(ui('Tasks'), 'பணிகள்');
  });
}
