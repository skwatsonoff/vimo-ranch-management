import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:ranch_management/main.dart';

void main() {
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('vimo_reports_');
    Hive.init(directory.path);
    for (final name in backupBoxNames) {
      await Hive.openBox(name);
    }
  });
  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  Future<void> show(WidgetTester tester, List<String> workspaces) async {
    await tester.runAsync(
      () => Hive.box('settings').put('purposeProfiles', {
        'local': {'purpose': workspaces.first, 'workspaces': workspaces},
      }),
    );
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: appleTheme(),
        home: const Scaffold(body: VendorOnlyReports()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('Reports show only the workspaces that are on', (tester) async {
    await show(tester, ['Ranch', 'Market']);
    expect(find.byType(ReportsScreen), findsOneWidget);
    expect(find.text('Vendor'), findsNothing);

    await show(tester, ['Vendor', 'Market']);
    expect(find.byType(ReportsScreen), findsNothing);
    expect(find.text('Customer profile reports'), findsOneWidget);

    await show(tester, ['Ranch', 'Vendor']);
    expect(find.text('Ranch'), findsOneWidget);
    expect(find.text('Vendor'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
