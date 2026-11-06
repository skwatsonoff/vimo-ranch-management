import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:ranch_management/voice_diagnostics.dart';
import 'package:ranch_management/voice_understanding.dart';

void main() {
  final now = DateTime(2026, 11, 6, 6, 15);

  test('the app version in reports matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(
      r'^version:\s*(\S+)',
      multiLine: true,
    ).firstMatch(pubspec)!.group(1);
    expect(vimoAppVersion, version);
  });

  test('a report starts with the header and schema version for Claude', () {
    final report = buildVoiceReport(events: const [], now: now);
    expect(report['header'], voiceReportHeader);
    expect(report['schemaVersion'], voiceReportSchemaVersion);
    expect(report['appVersion'], vimoAppVersion);
    // Plain JSON all the way down.
    expect(() => jsonEncode(report), returnsNormally);
    final md = voiceReportMarkdown(report);
    expect(md, startsWith('# VIMO voice report'));
    expect(md, contains(voiceReportHeader));
    expect(md, contains('Schema version: $voiceReportSchemaVersion'));
  });

  test('names are hidden, cows kept, contact details and money removed', () {
    final report = buildVoiceReport(
      events: [
        VoiceEvent(now, 'heard', {
          'text': 'Selvi ku 2 litre, call 98765 43210 or selvi@upi',
          'note': 'paid ₹500 and 200 rupees to Selvi',
          'cow': 'Lakshmi',
          'balance': 1200,
          'phone': '9876543210',
        }),
      ],
      people: ['Selvi'],
      cows: ['Lakshmi'],
      now: now,
    );
    final text = jsonEncode(report);
    expect(text, isNot(contains('Selvi')));
    expect(text, contains('person_1'));
    expect(text, contains('Lakshmi'));
    expect(text, isNot(contains('98765')));
    expect(text, isNot(contains('selvi@upi')));
    expect(text, isNot(contains('500')));
    expect(text, isNot(contains('1200')));
    // Dates and times are not mistaken for phone numbers.
    expect(text, contains('2026-11-06T06:15'));
  });

  test('names stay when the owner turns hiding off', () {
    final report = buildVoiceReport(
      events: [
        VoiceEvent(now, 'heard', {'text': 'Selvi ku 2 litre'}),
      ],
      people: ['Selvi'],
      hideNames: false,
      now: now,
    );
    expect(jsonEncode(report), contains('Selvi'));
  });

  test('the log keeps only the newest events', () async {
    final store = MemoryDiagnosticsStore();
    VoiceDiagnostics.store = store;
    for (int i = 0; i < VoiceDiagnostics.maxEvents + 25; i++) {
      await store.add(
        VoiceEvent(now, 'e$i', const {}),
        VoiceDiagnostics.maxEvents,
      );
    }
    final events = VoiceDiagnostics.events();
    expect(events, hasLength(VoiceDiagnostics.maxEvents));
    expect(events.first.type, 'e25');
    expect(events.last.type, 'e${VoiceDiagnostics.maxEvents + 24}');
  });

  test('the Hive log keeps its limit and order', () async {
    final dir = await Directory.systemTemp.createTemp('vimo_diag_');
    Hive.init(dir.path);
    await HiveDiagnosticsStore.open();
    final store = HiveDiagnosticsStore();
    for (int i = 0; i < 12; i++) {
      await store.add(VoiceEvent(now, 'e$i', {'n': i}), 10);
    }
    final events = store.load();
    expect(events.map((e) => e.type), [for (int i = 2; i < 12; i++) 'e$i']);
    expect(events.last.details['n'], 11);
    await store.clear();
    expect(store.load(), isEmpty);
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('self-test failures are listed in the Markdown summary', () {
    const cases = [
      VoiceTestCase('Lakshmi 5 litre', 'milk_record', {
        'cow': 'Lakshmi',
        'liters': 5,
      }),
      VoiceTestCase('Lakshmi 5 litre', 'milk_record', {'liters': 7}),
    ];
    final results = runVoiceSelfTest(
      cases,
      (t) => understandVoice(t, cows: const ['Lakshmi']),
    );
    expect(results.where((r) => r.passed), hasLength(1));
    final report = buildVoiceReport(
      events: const [],
      selfTest: results,
      now: now,
    );
    final md = voiceReportMarkdown(report);
    expect(md, contains('1 of 2 passed, 1 failed'));
    expect(md, contains('Self-test failures (1)'));
    expect(md, contains('"liters":7'));
  });

  test('slots compare names by sound and numbers by value', () {
    expect(slotsMatch({'cow': 'லட்சுமி'}, {'cow': 'Lakshmi'}), isTrue);
    expect(slotsMatch({'liters': 5}, {'liters': 5.0}), isTrue);
    expect(slotsMatch({'liters': 5}, {'liters': 6}), isFalse);
    expect(slotsMatch({'cow': null}, {'cow': 'Rani'}), isFalse);
    expect(slotsMatch({}, {'cow': 'Rani'}), isTrue);
  });

  test('live test results go into the report', () {
    final report = buildVoiceReport(
      events: const [],
      live: const [
        LiveTestResult(
          prompt: 'லட்சுமி 5 லிட்டர்',
          heard: 'லட்சுமி 9 லிட்டர்',
          understood: (intent: 'milk_record', slots: {'liters': 9}),
          matched: false,
          ownerSaysRight: false,
          correction: 'லட்சுமி 5 லிட்டர்',
        ),
      ],
      now: now,
    );
    final md = voiceReportMarkdown(report);
    expect(md, contains('WRONG'));
    expect(md, contains('owner says'));
  });
}
