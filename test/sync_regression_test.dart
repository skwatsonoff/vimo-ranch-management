import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image/image.dart' as image_lib;
import 'package:ranch_management/main.dart';
import 'package:ranch_management/sync_support.dart';

void main() {
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('vimo_sync_');
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
      'currentUser': 'Brother',
      'currentRole': 'Data Entry',
      'deviceId': 'test-brother',
      'autoSyncEnabled': false,
      'languageMode': 'English',
    });
  });
  tearDownAll(() async {
    AutoSyncService.stop();
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test(
    'worksheet names handle invalid edges, empty names and long Unicode',
    () {
      expect(excelWorksheetName('*Report'), 'Report');
      expect(excelWorksheetName('[Report]/'), 'Report');
      expect(excelWorksheetName(':\\/?*[]'), 'Sheet');
      expect(excelWorksheetName('  '), 'Sheet');
      expect(excelWorksheetName("'Report'"), 'Report');
      expect(excelWorksheetName('A' * 50), 'A' * 31);
      expect(excelWorksheetName('${'A' * 30}🐄Report'), 'A' * 30);
    },
  );

  test('latest milk is independent of cloud arrival order', () {
    final rows = [
      {'quantity': 2.0, 'date': '2026-09-01', 'time': '06:00'},
      {'quantity': 5.0, 'date': '2026-09-09', 'time': '17:00'},
      {'quantity': 3.0, 'date': '2026-09-09', 'time': '06:00'},
    ];
    expect(latestActivityFrom(rows)?['quantity'], 5.0);
    expect(latestActivityFrom(rows.reversed)?['quantity'], 5.0);
    expect(latestActivityFrom([]), isNull);
  });

  test(
    'home use reduces stock with zero revenue, including corrected entries',
    () async {
      await Hive.box(
        'milk_records',
      ).add({'quantity': 12.0, 'date': todayDate()});
      final home = <String, dynamic>{
        'type': 'Milk',
        'customerName': ownUseCustomerName,
        'quantity': 2.0,
        'pricePerUnit': 60.0,
        'amount': 120.0,
        'date': todayDate(),
      };
      applyMilkSaleUsage(home);
      await Hive.box('sale_records').add(home);
      await Hive.box('sale_records').add({
        'type': 'Milk',
        'customerName': 'Kumar',
        'quantity': 3.0,
        'pricePerUnit': 60.0,
        'amount': 180.0,
        'date': todayDate(),
      });
      expect(home['amount'], 0);
      expect(home['pricePerUnit'], 0);
      expect(milkOwnUse('Today'), 2);
      expect(milkSold('Today'), 3);
      expect(availableMilk('Today'), 7);
      expect(sumPeriod(saleRows(), 'amount', 'Today'), 180);
      home['quantity'] = 4.0;
      home['pricePerUnit'] = 90.0;
      applyMilkSaleUsage(home);
      expect(home['amount'], 0);
      home['customerName'] = 'Kumar';
      home['pricePerUnit'] = 60.0;
      applyMilkSaleUsage(home);
      expect(home['amount'], 240);
      expect(home['ownUse'], isFalse);
    },
  );

  test('a failed record does not stop independent uploads', () async {
    final delivered = <String>[];
    await expectLater(
      runSyncSteps({
        'milk': () async {
          delivered.add('milk');
        },
        'photo': () async {
          throw StateError('oversized image');
        },
        'sale': () async {
          delivered.add('sale');
        },
      }),
      throwsA(isA<SyncFailure>()),
    );
    expect(delivered, ['milk', 'sale']);
  });

  test(
    'manual sync waits for background sync and completes another pass',
    () async {
      final coordinator = SyncCoordinator();
      final network = Completer<void>();
      var runs = 0;
      Future<void> action() async {
        runs++;
        if (runs == 1) await network.future;
      }

      final background = coordinator.run(action);
      var manualDone = false;
      final manual = coordinator
          .run(action, rerun: true)
          .then((_) => manualDone = true);
      await Future<void>.delayed(Duration.zero);
      expect(manualDone, isFalse);
      expect(runs, 1);
      network.complete();
      await Future.wait([background, manual]);
      expect(runs, 2);
      expect(coordinator.running, isFalse);
    },
  );

  test(
    'sync failure reaches callers and does not leave the queue locked',
    () async {
      final coordinator = SyncCoordinator();
      await expectLater(
        coordinator.run(() async {
          throw StateError('denied');
        }),
        throwsStateError,
      );
      var retried = false;
      await coordinator.run(() async {
        retried = true;
      });
      expect(retried, isTrue);
    },
  );

  test('server acknowledgement preserves an edit made during upload', () async {
    final box = Hive.box('milk_records');
    final sent = <String, dynamic>{
      'cloudId': 'milk-one',
      'quantity': 2.0,
      'updatedAtMillis': 100,
      'pendingUpload': true,
      'nested': {'note': 'old'},
    };
    await box.put(1, sent);
    final edited = {
      ...sent,
      'quantity': 3.0,
      'nested': {'note': 'new'},
    };
    await box.put(1, edited);
    await CloudSyncService.acknowledge(box, 1, sent, {
      ...sent,
      'pendingUpload': false,
    });
    expect(box.get(1)['quantity'], 3);
    expect(box.get(1)['pendingUpload'], isTrue);
    await CloudSyncService.acknowledge(box, 1, edited, edited);
    expect(box.get(1)['pendingUpload'], isFalse);
  });

  test(
    'rapid local writes stay pending and remote echoes do not become uploads',
    () async {
      AutoSyncService.start();
      final box = Hive.box('milk_records');
      final keys = await Future.wait([
        box.add({'cow': 'Lakshmi', 'quantity': 2.0}),
        box.add({'cow': 'Ganga', 'quantity': 3.0}),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      for (final key in keys) {
        expect(box.get(key)['pendingUpload'], isTrue);
        expect(box.get(key)['cloudId'], isNotEmpty);
      }
      await AutoSyncService.putRemote(box, 'remote', {
        'cloudId': 'remote',
        'quantity': 4.0,
        'pendingUpload': false,
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(box.get('remote')['pendingUpload'], isFalse);
      await AutoSyncService.refreshPendingCount();
      expect(pendingSyncCount(), 2);
      AutoSyncService.stop();
    },
  );

  test(
    'health-only pending updates are counted without double counting animals',
    () async {
      await Hive.box('settings').put('pendingAnimalEntryUpdates', {
        'animal_c001': {'pregnancyStartDate': '2026-09-09'},
      });
      expect(AutoSyncService.countPending(), 1);
      await Hive.box(
        'animals',
      ).add({'cloudId': 'animal_c001', 'pendingUpload': true});
      expect(AutoSyncService.countPending(), 1);
    },
  );

  test('data entry sync cannot upload protected animal profiles', () {
    expect(CloudSyncService.mayUpload('animals', {}), isFalse);
    expect(CloudSyncService.mayUpload('settings', {}), isFalse);
    expect(CloudSyncService.mayUpload('milk_records', {}), isTrue);
    expect(
      CloudSyncService.mayUpload('sale_records', {'type': 'Milk'}),
      isTrue,
    );
    expect(
      CloudSyncService.mayUpload('sale_records', {'type': 'Cow'}),
      isFalse,
    );
  });

  test(
    'non-finite numeric input cannot crash integer conversion or poison totals',
    () {
      expect(toInt(double.nan), 0);
      expect(toInt(double.infinity), 0);
      expect(toDouble('NaN'), 0);
      expect(toDouble('Infinity'), 0);
      expect(numv({'quantity': double.nan}, 'quantity'), 0);
    },
  );

  testWidgets(
    'home-use selection locks price to zero and restores paid price',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SellScreen())),
      );
      await tester.pump(const Duration(seconds: 1));
      final choice = find.byKey(const ValueKey('own-use-customer'));
      await tester.ensureVisible(choice);
      await tester.tap(choice);
      await tester.pump();
      final price = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Price per Liter',
      );
      expect(tester.widget<TextField>(price).controller!.text, '0');
      expect(tester.widget<TextField>(price).readOnly, isTrue);
      await tester.tap(choice);
      await tester.pump();
      expect(tester.widget<TextField>(price).controller!.text, '60');
      expect(tester.widget<TextField>(price).readOnly, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('full photo opens fitted to the screen and supports zoom', (
    tester,
  ) async {
    final picture = image_lib.Image(width: 400, height: 100);
    final provider = MemoryImage(
      Uint8List.fromList(image_lib.encodePng(picture)),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AnimalPhotoViewer(image: provider, name: 'Lakshmi'),
      ),
    );
    await tester.pump();
    expect(tester.widget<Image>(find.byType(Image)).fit, BoxFit.contain);
    expect(
      tester.widget<InteractiveViewer>(find.byType(InteractiveViewer)).maxScale,
      5,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
