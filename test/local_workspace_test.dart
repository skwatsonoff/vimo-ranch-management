import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart' hide Ink;
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image/image.dart' as image_lib;
import 'package:ranch_management/main.dart';

void main() {
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('vimo_local_');
    Hive.init(directory.path);
    for (final name in [...backupBoxNames, 'device_workspaces']) {
      await Hive.openBox(name);
    }
  });
  setUp(() async {
    AutoSyncService.stop();
    for (final name in [...backupBoxNames, 'device_workspaces']) {
      await Hive.box(name).clear();
    }
    await Hive.box('settings').putAll({
      'currentRole': 'Admin',
      'languageMode': 'English',
      'firebaseUid': 'owner',
      'ranchId': 'home',
    });
  });
  tearDownAll(() async {
    AutoSyncService.stop();
    await Hive.close();
    await directory.delete(recursive: true);
  });
  const provider = {'id': 'supplier', 'name': 'Kalai', 'kind': 'supplier'};
  const buyer = {'id': 'buyer', 'name': 'Vijay', 'kind': 'customer'};

  test(
    'Production entries save offline, survive reopen and retry without duplicates',
    () async {
      expect(firebaseReady, false);
      await VendorLedger.record(
        id: 'purchase',
        person: provider,
        kind: 'purchase',
        quantity: 5,
        price: 40,
      );
      await VendorLedger.record(
        id: 'sale',
        person: buyer,
        kind: 'sale',
        quantity: 2,
        price: 60,
        paid: 60,
      );
      await VendorLedger.record(
        id: 'sale',
        person: buyer,
        kind: 'sale',
        quantity: 2,
        price: 60,
        paid: 60,
      );
      await VendorLedger.record(
        id: 'receipt',
        person: buyer,
        kind: 'payment',
        payment: 60,
      );
      await Hive.box('vendor_entries').close();
      await Hive.openBox('vendor_entries');
      final rows = vendorRows('vendor_entries');
      expect(rows.length, 3);
      expect(vendorMilkBalance(rows), 3);
      expect(vendorPersonDue('buyer', rows), 0);
      expect(rows.every((r) => r['pendingUpload'] == true), true);
      expect(
        AutoSyncService.countPending(),
        0,
      ); // private entries are not a cloud queue
      await Hive.box('settings').put('workspaceSyncEnabled', true);
      expect(AutoSyncService.countPending(), 3);
    },
  );
  test(
    'Invalid stock and excessive receipt fail before creating any local row',
    () async {
      await expectLater(
        VendorLedger.record(
          id: 'empty',
          person: buyer,
          kind: 'sale',
          quantity: 1,
          price: 60,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Add the milk'),
          ),
        ),
      );
      await expectLater(
        VendorLedger.record(
          id: 'overpaid',
          person: buyer,
          kind: 'payment',
          payment: 60,
        ),
        throwsStateError,
      );
      expect(Hive.box('vendor_entries').isEmpty, true);
      await VendorLedger.record(
        id: 'valid',
        person: provider,
        kind: 'purchase',
        quantity: 1,
        price: 40,
      );
      expect(Hive.box('vendor_entries').length, 1);
    },
  );
  test(
    'Purpose hides secondary mode until enabled and selects the correct destinations',
    () async {
      await savePurpose('Ranch', defaultNavigation('Ranch'));
      expect(navigationOrder(), ['Ranch', 'Social', 'Chat', 'Profile']);
      await savePurpose(
        'Ranch',
        defaultNavigation('Ranch', secondaryEnabled: true),
        secondaryEnabled: true,
      );
      expect(navigationOrder(), ['Ranch', 'Vendor', 'Social', 'Chat']);
      await savePurpose('Vendor', defaultNavigation('Vendor'));
      expect(navigationOrder(), ['Vendor', 'Reports', 'Social', 'Chat']);
      await savePurpose(
        'Vendor',
        defaultNavigation('Vendor', secondaryEnabled: true),
        secondaryEnabled: true,
      );
      expect(navigationOrder(), ['Vendor', 'Ranch', 'Reports', 'Social']);
      await Hive.box('settings').put('purposeProfiles', {
        'local': {
          'purpose': 'Ranch',
          'order': ['Ranch', 'Vendor', 'Social', 'Chat'],
        },
      });
      expect(navigationOrder(), ['Ranch', 'Social', 'Chat', 'Profile']);
    },
  );
  test(
    'Account changes preserve private ranch and vendor data on the device',
    () async {
      await DeviceWorkspaces.restore();
      await Hive.box('milk_records').put(7, {'quantity': 10});
      await VendorLedger.record(
        id: 'milk',
        person: provider,
        kind: 'purchase',
        quantity: 5,
        price: 40,
      );
      await RanchAccessService.clearLocalRanchData();
      await RanchAccessService.clearLocalRanchData(); // no empty archive overwrite
      await Hive.box('settings').put('firebaseUid', 'other');
      await DeviceWorkspaces.restore();
      expect(Hive.box('vendor_entries').isEmpty, true);
      await Hive.box('milk_records').put('other', {'quantity': 2});
      await RanchAccessService.clearLocalRanchData();
      await Hive.box('settings').put('firebaseUid', 'owner');
      await DeviceWorkspaces.restore();
      expect(Hive.box('milk_records').get(7)['quantity'], 10);
      expect(Hive.box('milk_records').containsKey('other'), false);
      expect(vendorMilkBalance(vendorRows('vendor_entries')), 5);
    },
  );
  test(
    'Payment timing distinguishes due now, recent receipts and future due dates',
    () {
      final date = DateTime(2026, 9, 26);
      expect(vendorPaymentTiming(buyer, [], date).color, Ink.amberText);
      expect(
        vendorPaymentTiming(
          {
            ...buyer,
            'paymentCycle': 'Weekly',
            'paymentDays': [0],
          },
          [],
          date,
        ).label,
        'Due tomorrow',
      );
      expect(
        vendorPaymentTiming(
          {
            ...buyer,
            'paymentCycle': 'Weekly',
            'paymentDays': [0],
          },
          [],
          date,
        ).color,
        Ink.redText,
      );
      expect(
        vendorPaymentTiming(buyer, [
          {
            'personId': 'buyer',
            'kind': 'sale',
            'amount': 60,
            'paid': 60,
            'date': '2026-09-25',
          },
        ], date).label,
        'Received yesterday',
      );
      expect(
        vendorPaymentTiming(buyer, [
          {
            'personId': 'buyer',
            'kind': 'sale',
            'amount': 60,
            'paid': 60,
            'date': '2026-09-25',
          },
        ], date).color,
        Ink.greenText,
      );
    },
  );
  test(
    'Social photo keeps 1600px detail within the existing media limit',
    () async {
      final image = image_lib.Image(width: 2400, height: 1600);
      image_lib.fill(image, color: image_lib.ColorRgb8(122, 54, 199));
      final encoded = await compressSocialPhoto(
        'data:image/png;base64,${base64Encode(image_lib.encodePng(image))}',
      );
      expect(encoded, isNotNull);
      expect(encoded!.length, lessThan(600000));
      expect(image_lib.decodeJpg(socialPhotoBytes(encoded))!.width, 1600);
    },
  );
  testWidgets('Person entry retains field headings and infers its session', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: VendorPersonScreen(
          person: {
            ...provider,
            'quantity': 1.0,
            'price': 60.0,
            'place': 'PCM',
            'paymentCycle': 'Weekly',
          },
        ),
      ),
    );
    await tester.pump();
    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .toList();
    expect(
      fields.map((f) => f.decoration?.labelText),
      containsAll([
        'Milk quantity (litres)',
        'Price per litre',
        'Amount paid now (0 for later)',
      ]),
    );
    expect(
      fields.every(
        (f) =>
            f.decoration?.floatingLabelBehavior == FloatingLabelBehavior.always,
      ),
      true,
    );
    expect(find.byType(ChoiceChip), findsNothing);
    expect(
      tester
          .widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>))
          .showSelectedIcon,
      false,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
