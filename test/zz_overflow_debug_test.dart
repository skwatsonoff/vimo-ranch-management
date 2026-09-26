// Temporary diagnostic: prints full layout error details. Removed after use.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:ranch_management/main.dart';

void main() {
  late Directory dir;
  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('vimo_dbg_');
    Hive.init(dir.path);
    for (final name in backupBoxNames) {
      await Hive.openBox(name);
    }
  });
  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });
  testWidgets('debug overflow in completed ride', (tester) async {
    final previous = FlutterError.onError;
    final seen = <String>[];
    FlutterError.onError = (details) {
      final text = details.toString();
      final lines = text
          .split('\n')
          .where(
            (l) =>
                l.contains('overflowed') ||
                l.contains('lib/') ||
                l.contains('creator') ||
                l.contains('constraints') ||
                l.contains('size:') ||
                l.contains('relevant'),
          )
          .take(14)
          .join(' | ');
      seen.add(lines);
    };
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    await tester.runAsync(() async {
      await Hive.box('settings').putAll({
        'languageMode': 'English',
        'currentRole': 'Admin',
        'deviceId': 'ride-test',
        'defaultMilkPrice': 60,
      });
      await Hive.box('vendor_people').put('Kumar', {
        'id': 'Kumar',
        'cloudId': 'Kumar',
        'kind': 'customer',
        'name': 'Kumar',
        'place': 'Erode',
        'quantity': 2.0,
        'price': 60.0,
        'days': <int>[],
        'sessions': ['Morning', 'Evening'],
        'paymentCycle': 'Daily',
      });
      await Hive.box('vendor_entries').putAll({
        'supply': {
          'cloudId': 'supply',
          'kind': 'collection',
          'stockScope': 'vendor_v2',
          'quantity': 10,
          'amount': 400,
          'paid': 400,
          'personId': 'supplier',
        },
        'old-sale': {
          'cloudId': 'old-sale',
          'kind': 'sale',
          'stockScope': 'vendor_v2',
          'quantity': 1,
          'amount': 60,
          'paid': 0,
          'personId': 'Kumar',
        },
      });
    });
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: VendorRideScreen())),
    );
    await tester.pump(const Duration(milliseconds: 600));
    seen.add('--- after mount');
    await tester.runAsync(() async {
      await tester.tap(find.text('Start'));
      await Future<void>.delayed(const Duration(milliseconds: 40));
    });
    await tester.pump(const Duration(milliseconds: 1900));
    seen.add('--- after start');
    final card = find
        .ancestor(of: find.text('Kumar'), matching: find.byType(Glass))
        .first;
    await tester.runAsync(() async {
      await tester.drag(card, const Offset(160, 0));
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    seen.add('--- after complete');
    await tester.ensureVisible(find.text('End'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('End'));
      await Future<void>.delayed(const Duration(milliseconds: 40));
    });
    await tester.pumpAndSettle();
    seen.add('--- after summary');
    FlutterError.onError = previous;
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    // ignore: avoid_print
    print('DEBUG_OVERFLOW ${seen.join(' ### ')}');
    fail('diagnostic ${seen.join(' ### ')}');
  });
}
