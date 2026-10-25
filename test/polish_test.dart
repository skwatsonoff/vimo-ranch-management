import 'dart:io';
import 'dart:math' as math;

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
      expect(milkSessionForTime(DateTime(2026, 1, 1, 10, 59)), 'Morning');
      expect(milkSessionForTime(DateTime(2026, 1, 1, 11)), 'Afternoon');
      expect(milkSessionForTime(DateTime(2026, 1, 1, 15, 59)), 'Afternoon');
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
      expect(lastMilkQuantityFor('Lakshmi', 'Afternoon'), isNull);
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
    await tester.tap(find.text('Milk'));
    await tester.pump();
    expect(added, 1);
    await tester.tap(find.text('10.5 L'));
    await tester.pumpAndSettle();
    expect(opened, 1);
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
