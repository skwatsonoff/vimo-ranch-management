import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' hide Ink;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:ranch_management/main.dart';

/// Covers the polish pass: design tokens, the Home milk card, counting
/// numbers, state panels, milk entry shortcuts and the sound switch.
void main() {
  late Directory dir;
  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('vimo_polish_');
    Hive.init(dir.path);
    for (final name in backupBoxNames) {
      await Hive.openBox(name);
    }
  });
  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  String day(int offset) {
    final d = DateTime.now().add(Duration(days: offset));
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  Future<void> addCow(String name) => Hive.box('animals').add({
    'type': 'cow',
    'name': name,
    'id': name.substring(0, 2).toUpperCase(),
    'status': 'Active',
    'gender': 'Female',
  });

  Future<void> addMilk(
    String cow,
    String session,
    double quantity, {
    int dayOffset = 0,
    String time = '07:00',
  }) => Hive.box('milk_records').add({
    'cow': cow,
    'session': session,
    'quantity': quantity,
    'date': day(dayOffset),
    'time': time,
    'createdAt': '${day(dayOffset)}T$time:00',
  });

  setUp(() async {
    for (final name in backupBoxNames) {
      await Hive.box(name).clear();
    }
    await Hive.box('settings').putAll({
      'languageMode': 'English',
      'currentRole': 'Admin',
      'currentUser': 'Appa',
      'deviceId': 'polish-test',
      'defaultMilkPrice': 60,
    });
  });

  Widget app(Widget home, {bool reduceMotion = false}) => MaterialApp(
    supportedLocales: const [Locale('en'), Locale('ta')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
      child: child!,
    ),
    home: home,
  );

  testWidgets('Walk-in sale sells Rs 20 of milk paid on the spot', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(
      () => VendorLedger.record(
        id: 'in',
        person: const {'id': 's', 'name': 'Kalai', 'kind': 'supplier'},
        kind: 'purchase',
        quantity: 5,
        price: 40,
      ),
    );
    await tester.runAsync(
      () => Hive.box('settings').put('vendorWalkInPrice', 60),
    );
    await tester.pumpWidget(
      app(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showWalkInSale(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Walk-in customer'), findsOneWidget);
    expect(find.text('Gives 333 ml for ₹20, paid now'), findsOneWidget);
    await tester.tap(find.text('₹10'));
    await tester.pump();
    expect(find.text('Gives 167 ml for ₹10, paid now'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.text('Sold · ₹10'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    final sale = vendorRows(
      'vendor_entries',
    ).firstWhere((r) => r['personKind'] == 'walkin');
    expect(numv(sale, 'paid'), 10);
    expect(numv(sale, 'amount'), 10);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Fridge shows what is left and how long it keeps', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      await VendorLedger.record(
        id: 'in',
        person: const {'id': 's', 'name': 'Kalai', 'kind': 'supplier'},
        kind: 'purchase',
        quantity: 5,
        price: 40,
      );
      await VendorLedger.record(
        id: 'lot',
        person: vendorFridge,
        kind: 'clearance',
        quantity: 2,
      );
    });
    await tester.pumpWidget(app(const FridgeScreen()));
    await tester.pumpAndSettle();
    expect(find.text('2 L'), findsWidgets);
    expect(find.textContaining('h left'), findsOneWidget);
    expect(find.text('Make curd'), findsOneWidget);
    expect(find.text('Sell'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('voice notes', () {
    Uint8List tone(int rate, int channels, double seconds) {
      final frames = (rate * seconds).round();
      final data = ByteData(frames * channels * 2);
      for (var f = 0; f < frames; f++) {
        final v = (math.sin(2 * math.pi * 300 * f / rate) * 12000).round();
        for (var c = 0; c < channels; c++) {
          data.setInt16((f * channels + c) * 2, v, Endian.little);
        }
      }
      return data.buffer.asUint8List();
    }

    test('48 kHz stereo from a browser becomes 8 kHz mono, same length', () {
      final out = pcm16ToVoiceRate(
        tone(48000, 2, 2),
        VoiceFormat(48000, 2),
        8000,
      );
      // Two seconds at 8 kHz, 16-bit mono.
      expect(out.length, 2 * 8000 * 2);
      final view = ByteData.sublistView(out);
      var peak = 0;
      for (var i = 0; i < out.length; i += 2) {
        peak = math.max(peak, view.getInt16(i, Endian.little).abs());
      }
      // The 300 Hz voice band survives the averaging.
      expect(peak, greaterThan(9000));
    });

    test('8 kHz mono is left as it is', () {
      final input = tone(8000, 1, .5);
      expect(pcm16ToVoiceRate(input, VoiceFormat(8000), 8000), input);
    });

    test('44.1 kHz rounds to whole samples', () {
      final out = pcm16ToVoiceRate(tone(44100, 1, 1), VoiceFormat(44100), 8000);
      expect(out.length, 16000);
    });
  });

  group('tokens', () {
    test('spacing sits on the 4-point grid', () {
      for (final v in [
        Space.s4,
        Space.s8,
        Space.s12,
        Space.s16,
        Space.s20,
        Space.s24,
        Space.s28,
        Space.s32,
        Space.s56,
        Space.s88,
      ]) {
        expect(v % 4, 0, reason: '$v');
      }
      expect(Space.target, 44);
    });

    test('the house spring is critically damped', () {
      final s = Motion.standard;
      final ratio = s.damping / (2 * math.sqrt(s.stiffness * s.mass));
      expect(ratio, closeTo(1.0, 1e-9));
      final m = Motion.momentum;
      expect(
        m.damping / (2 * math.sqrt(m.stiffness * m.mass)),
        closeTo(.8, 1e-9),
      );
    });

    test('brand tint keeps white labels and tinted text readable', () {
      double luminance(Color c) => c.computeLuminance();
      double contrast(Color a, Color b) {
        final la = luminance(a), lb = luminance(b);
        return (math.max(la, lb) + .05) / (math.min(la, lb) + .05);
      }

      for (final dark in [false, true]) {
        Ink.dark = dark;
        expect(contrast(Colors.white, Ink.tint), greaterThan(4.5));
        expect(contrast(Ink.violetDeep, Ink.canvasTop), greaterThan(4.5));
        expect(contrast(Ink.orangeText, Ink.surface), greaterThan(4.5));
        expect(contrast(Ink.muted, Ink.canvasTop), greaterThan(4.5));
      }
      Ink.dark = false;
    });
  });

  group('milk helpers', () {
    test('session follows the clock', () {
      expect(milkSessionForTime(DateTime(2026, 1, 1, 5, 30)), 'Morning');
      expect(milkSessionForTime(DateTime(2026, 1, 1, 11, 59)), 'Morning');
      expect(milkSessionForTime(DateTime(2026, 1, 1, 12)), 'Evening');
      expect(milkSessionForTime(DateTime(2026, 1, 1, 16)), 'Evening');
      expect(milkSessionForTime(DateTime(2026, 1, 1, 23)), 'Evening');
    });

    test('litres format without noise', () {
      expect(formatLitres(0), '0 L');
      expect(formatLitres(12), '12 L');
      expect(formatLitres(6.25), '6.3 L');
      expect(formatLitres(6.04), '6 L');
    });

    test('last quantity and today total per cow and session', () async {
      await addMilk('Lakshmi', 'Morning', 6, dayOffset: -2);
      await addMilk('Lakshmi', 'Morning', 6.5, dayOffset: -1);
      await addMilk('Lakshmi', 'Evening', 4, dayOffset: -1);
      await addMilk('Lakshmi', 'Morning', 7);
      await addMilk('Ganga', 'Morning', 9);
      expect(lastMilkQuantityFor('Lakshmi', 'Morning'), 7);
      expect(lastMilkQuantityFor('Lakshmi', 'Evening'), 4);
      expect(lastMilkQuantityFor('Ganga', 'Evening'), isNull);
      expect(milkRecordedFor('Lakshmi', 'Morning', todayDate()), 7);
      expect(milkRecordedFor('Lakshmi', 'Evening', todayDate()), 0);
    });

    test('expense name offers its last amount', () async {
      final box = Hive.box('expense_records');
      await box.add({
        'name': 'Diesel',
        'amount': 500.0,
        'date': day(-3),
        'createdAt': '${day(-3)}T08:00:00',
      });
      await box.add({
        'name': 'diesel',
        'amount': 650.0,
        'date': day(-1),
        'createdAt': '${day(-1)}T08:00:00',
      });
      expect(lastExpenseAmountFor('Diesel '), 650);
      expect(lastExpenseAmountFor('Rope'), isNull);
    });
  });

  test('A deleted vendor customer leaves lists but keeps history', () async {
    final box = Hive.box('vendor_people');
    await box.put('p1', {
      'id': 'p1',
      'kind': 'customer',
      'name': 'Selvi',
      'place': 'Chennai',
      'days': <int>[],
      'sessions': ['Morning', 'Evening'],
    });
    expect(activeVendorPeople().length, 1);
    final person = vendorRows('vendor_people').first;
    await setVendorPersonRemoved(person, true);
    expect(activeVendorPeople(), isEmpty);
    // Still stored for reports and Undo.
    expect(vendorRows('vendor_people').single['name'], 'Selvi');
    expect(
      vendorRoutePeople(
        vendorRows('vendor_people'),
        const [],
        DateTime.now(),
        'Morning',
      ),
      isEmpty,
    );
    await setVendorPersonRemoved(person, false);
    expect(activeVendorPeople().length, 1);
  });

  testWidgets('Today\'s milk card totals the day against yesterday', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await addMilk('Lakshmi', 'Morning', 6);
      await addMilk('Ganga', 'Evening', 4.5, time: '18:00');
      await addMilk('Lakshmi', 'Morning', 8, dayOffset: -1);
    });
    var added = 0;
    var opened = 0;
    await tester.pumpWidget(
      app(
        Scaffold(
          body: TodayMilkCard(onOpen: () => opened++, onAdd: () => added++),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('10.5 L'), findsOneWidget);
    expect(find.text('6 L'), findsOneWidget);
    expect(find.text('4.5 L'), findsOneWidget);
    expect(find.text('+2.5 L vs yesterday'), findsOneWidget);
    // Twice-a-day milking: no afternoon session unless old data has one.
    expect(find.text('Afternoon'), findsNothing);
    await tester.tap(find.text('Milk'));
    await tester.pump();
    expect(added, 1);
    await tester.tap(find.text('10.5 L'));
    await tester.pumpAndSettle();
    expect(opened, 1);
  });

  testWidgets('Today\'s milk card fits Tamil at 320 pt with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      await Hive.box('settings').put('languageMode', 'Tamil');
      await addMilk('Lakshmi', 'Morning', 1234.5);
    });
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.6)),
          child: child!,
        ),
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [TodayMilkCard(onOpen: () {}, onAdd: () {})],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('இன்றைய பால்'), findsOneWidget);
    expect(find.text('காலை'), findsOneWidget);
  });

  testWidgets('Home fits Tamil on a small phone with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      await Hive.box('settings').put('languageMode', 'Tamil');
      await addCow('Lakshmi');
      await addMilk('Lakshmi', 'Evening', 12, time: '18:00');
    });
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.4)),
          child: child!,
        ),
        home: Scaffold(body: DashboardScreen(onOpenCard: (_) {})),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(ListView).first, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Numbers count up to the new value, or jump with Reduce Motion', (
    tester,
  ) async {
    Widget counter(double v, {bool reduce = false}) => app(
      Scaffold(
        body: CountUpText(value: v, format: (x) => x.toStringAsFixed(0)),
      ),
      reduceMotion: reduce,
    );
    await tester.pumpWidget(counter(10));
    expect(find.text('10'), findsOneWidget);
    await tester.pumpWidget(counter(110));
    await tester.pump(const Duration(milliseconds: 100));
    final midway = tester.widget<Text>(find.byType(Text)).data!;
    expect(int.parse(midway), inExclusiveRange(10, 110));
    await tester.pumpAndSettle();
    expect(find.text('110'), findsOneWidget);

    await tester.pumpWidget(counter(5, reduce: true));
    await tester.pumpWidget(counter(50, reduce: true));
    await tester.pump();
    expect(find.text('50'), findsOneWidget);
  });

  testWidgets('A state panel names the way forward', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      app(
        Scaffold(
          body: StatePanel(
            icon: CupertinoIcons.wifi_slash,
            title: 'Nothing here yet',
            message: 'Add the first one.',
            actionLabel: 'Add',
            onAction: () => taps++,
          ),
        ),
      ),
    );
    expect(find.text('Nothing here yet'), findsOneWidget);
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('Add Entry keeps all three choices in Tamil', (tester) async {
    await tester.runAsync(() async {
      await Hive.box('settings').put('languageMode', 'Tamil');
      await addCow('Lakshmi');
    });
    await tester.pumpWidget(app(const AddEntryScreen()));
    await tester.pumpAndSettle();
    expect(find.text('பால்'), findsWidgets);
    expect(find.text('தீவனம்'), findsOneWidget);
    expect(find.text('இதர செலவு'), findsOneWidget);
    expect(find.text('காலை'), findsOneWidget);
    expect(find.text('மாலை'), findsOneWidget);
    expect(find.text('மதியம்'), findsNothing);
    await tester.tap(find.text('இதர செலவு'));
    await tester.pumpAndSettle();
    expect(find.text('செலவின் பெயர்'), findsOneWidget);
  });

  testWidgets('Save & Next Cow records and moves on without leaving', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      await addCow('Lakshmi');
      await addCow('Ganga');
      await addMilk(
        'Lakshmi',
        milkSessionForTime(DateTime.now()),
        6.5,
        dayOffset: -1,
      );
    });
    await tester.pumpWidget(app(const AddEntryScreen()));
    await tester.pumpAndSettle();
    // The cow's usual quantity is one tap away.
    expect(find.text('Last: 6.5 L'), findsOneWidget);
    await tester.tap(find.text('Last: 6.5 L'));
    await tester.pump();
    expect(find.widgetWithText(TextField, '6.5'), findsOneWidget);

    // Hive writes are real I/O, so the save runs outside the fake clock.
    await tester.runAsync(() async {
      await tester.tap(find.text('Save & Next Cow'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(Hive.box('milk_records').length, 2);
    expect(find.byType(AddEntryScreen), findsOneWidget);
    // Lakshmi is done, so Ganga is up next with an empty quantity.
    expect(find.text('Ganga'), findsWidgets);
    expect(find.widgetWithText(TextField, '6.5'), findsNothing);
    expect(find.byIcon(CupertinoIcons.checkmark_circle_fill), findsOneWidget);
  });

  testWidgets('The Sounds switch is on by default and remembers off', (
    tester,
  ) async {
    expect(UiSound.enabled, isTrue);
    await tester.pumpWidget(app(const AppSettingsScreen()));
    await tester.pumpAndSettle();
    final sounds = find.byType(SoundSwitch);
    expect(sounds, findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(sounds);
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(UiSound.enabled, isFalse);
    expect(settingValue(UiSound.settingKey, true), isFalse);
  });
}
