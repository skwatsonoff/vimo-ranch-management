/// VIMO's voice diagnostics: a log of what the voice assistant heard,
/// understood and did, and the report the owner downloads and gives to
/// Claude so a problem can be found without the phone.
///
/// The log lives only on this phone (Hive box `voice_diagnostics`, the last
/// [VoiceDiagnostics.maxEvents] events). It is never backed up or synced.
library;

import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import 'voice_parser.dart' show phoneticKey, soundSimilarity;

/// The app version written into reports. Keep equal to `version:` in
/// pubspec.yaml (a test checks this).
const vimoAppVersion = '1.5.1+10';

/// Bumped whenever the report's JSON layout changes.
const voiceReportSchemaVersion = 1;

const voiceReportHeader =
    'This is a VIMO voice diagnostics report. Use it to find and fix voice, '
    'language, permission and model problems in '
    'skwatsonoff/vimo-ranch-management.';

/// One thing that happened.
class VoiceEvent {
  final DateTime time;
  final String type;
  final Map<String, Object?> details;

  const VoiceEvent(this.time, this.type, this.details);

  Map<String, Object?> toJson() => {
    't': time.toIso8601String(),
    'type': type,
    'd': details,
  };

  static VoiceEvent? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final time = DateTime.tryParse('${raw['t']}');
    if (time == null) return null;
    final d = raw['d'];
    return VoiceEvent(
      time,
      '${raw['type']}',
      d is Map ? d.map((k, v) => MapEntry('$k', v)) : const {},
    );
  }
}

/// Where events are kept: Hive in the app, memory in tests.
abstract class DiagnosticsStore {
  List<VoiceEvent> load();
  Future<void> add(VoiceEvent event, int keep);
  Future<void> clear();
}

class MemoryDiagnosticsStore implements DiagnosticsStore {
  final List<VoiceEvent> events = [];
  @override
  List<VoiceEvent> load() => List.of(events);
  @override
  Future<void> add(VoiceEvent event, int keep) async {
    events.add(event);
    if (events.length > keep) events.removeRange(0, events.length - keep);
  }

  @override
  Future<void> clear() async => events.clear();
}

/// Hive box `voice_diagnostics`: auto-increment keys keep the order; the
/// oldest are deleted past the limit.
class HiveDiagnosticsStore implements DiagnosticsStore {
  static const boxName = 'voice_diagnostics';

  Box? get _box => Hive.isBoxOpen(boxName) ? Hive.box(boxName) : null;

  static Future<void> open() async {
    if (!Hive.isBoxOpen(boxName)) await Hive.openBox(boxName);
  }

  @override
  List<VoiceEvent> load() {
    final box = _box;
    if (box == null) return const [];
    return box.values.map(VoiceEvent.fromJson).whereType<VoiceEvent>().toList();
  }

  @override
  Future<void> add(VoiceEvent event, int keep) async {
    final box = _box;
    if (box == null) return;
    // Plain JSON types only, so any value can be stored.
    await box.add(jsonDecode(jsonEncode(event.toJson(), toEncodable: _plain)));
    final extra = box.length - keep;
    if (extra > 0) await box.deleteAll(box.keys.take(extra).toList());
  }

  @override
  Future<void> clear() async => _box?.clear();
}

Object? _plain(Object? value) => '$value';

/// The shared log.
class VoiceDiagnostics {
  VoiceDiagnostics._();

  static const maxEvents = 2000;
  static DiagnosticsStore store = HiveDiagnosticsStore();

  /// Fixed facts about this session, added to every report.
  static final Map<String, Object?> context = {};

  static void log(String type, [Map<String, Object?> details = const {}]) {
    try {
      final event = VoiceEvent(DateTime.now(), type, details);
      // Writing must never slow or break voice: fire and forget.
      store.add(event, maxEvents).catchError((_) {});
    } catch (_) {}
  }

  static List<VoiceEvent> events() {
    try {
      return store.load();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> clear() => store.clear();
}

// --- self-test -------------------------------------------------------------------

/// One sentence with what VIMO should understand from it.
class VoiceTestCase {
  final String text;
  final String intent;
  final Map<String, Object?> slots;
  final String language;

  const VoiceTestCase(
    this.text,
    this.intent, [
    this.slots = const {},
    this.language = '',
  ]);

  static VoiceTestCase fromJson(Map<String, dynamic> json) => VoiceTestCase(
    '${json['text']}',
    '${json['intent']}',
    Map<String, Object?>.from((json['slots'] as Map?) ?? const {}),
    '${json['lang'] ?? ''}',
  );
}

/// What the understanding produced for a sentence.
typedef VoiceReading = ({String intent, Map<String, Object?> slots});
typedef VoiceInterpreter = VoiceReading Function(String text);

class VoiceTestResult {
  final VoiceTestCase testCase;
  final VoiceReading got;
  final bool passed;
  const VoiceTestResult(this.testCase, this.got, this.passed);

  Map<String, Object?> toJson() => {
    'text': testCase.text,
    'lang': testCase.language,
    'expected': {'intent': testCase.intent, 'slots': testCase.slots},
    'got': {'intent': got.intent, 'slots': got.slots},
    'passed': passed,
  };
}

/// True when every expected slot is in [got] with the same value. Names
/// compare by sound ("மைனா" equals "Maina"), numbers by value.
bool slotsMatch(Map<String, Object?> expected, Map<String, Object?> got) {
  for (final entry in expected.entries) {
    final want = entry.value;
    final have = got[entry.key];
    if (want == null) {
      if (have != null) return false;
      continue;
    }
    if (have == null) return false;
    if (want is num || have is num) {
      final a = want is num ? want.toDouble() : double.tryParse('$want');
      final b = have is num ? have.toDouble() : double.tryParse('$have');
      if (a == null || b == null || (a - b).abs() > 1e-6) return false;
      continue;
    }
    if (want is List) {
      if (have is! List) return false;
      final a = want.map((e) => '$e').toSet();
      final b = have.map((e) => '$e').toSet();
      if (!a.containsAll(b) || !b.containsAll(a)) return false;
      continue;
    }
    if (want is bool || have is bool) {
      if ('$want' != '$have') return false;
      continue;
    }
    if ('$want'.toLowerCase() == '$have'.toLowerCase()) continue;
    // Same name in another script or spelling: "லட்சுமி" is "Lakshmi".
    if (soundSimilarity(phoneticKey('$want'), phoneticKey('$have')) < .8) {
      return false;
    }
  }
  return true;
}

List<VoiceTestResult> runVoiceSelfTest(
  List<VoiceTestCase> cases,
  VoiceInterpreter interpret,
) => [
  for (final c in cases)
    () {
      VoiceReading got;
      try {
        got = interpret(c.text);
      } catch (error) {
        got = (intent: 'error', slots: {'error': '$error'});
      }
      final passed = got.intent == c.intent && slotsMatch(c.slots, got.slots);
      return VoiceTestResult(c, got, passed);
    }(),
];

/// One sentence the owner read aloud in the live microphone test.
class LiveTestResult {
  final String prompt;
  final String heard;
  final double? confidence;
  final VoiceReading understood;
  final bool matched;

  /// The owner's verdict: true right, false wrong, null not marked.
  final bool? ownerSaysRight;
  final String correction;

  const LiveTestResult({
    required this.prompt,
    required this.heard,
    required this.understood,
    required this.matched,
    this.confidence,
    this.ownerSaysRight,
    this.correction = '',
  });

  Map<String, Object?> toJson() => {
    'prompt': prompt,
    'heard': heard,
    'confidence': confidence,
    'understood': {'intent': understood.intent, 'slots': understood.slots},
    'matched': matched,
    'ownerSaysRight': ownerSaysRight,
    'correction': correction,
  };
}

// --- privacy -------------------------------------------------------------------

/// Removes what must not leave the phone: person names (when [hideNames]),
/// phone numbers, emails, UPI ids and money. Cow names stay: they are what
/// voice matching is about.
class ReportScrubber {
  ReportScrubber({required this.hideNames, Iterable<String> people = const []})
    : _people = {
        for (final p in people)
          if (p.trim().length > 1) p.trim(),
      }.toList()..sort((a, b) => b.length.compareTo(a.length));

  final bool hideNames;
  final List<String> _people;
  final Map<String, String> _aliases = {};

  static final _email = RegExp(r'[\w.+-]+@[\w-]+(\.[\w-]+)*');
  // Indian mobiles (98765 43210, +91-9876543210) and long digit runs;
  // dates and times ("2026-11-06") are left alone.
  static final _phone = RegExp(
    r'(?<![\d-])((\+?91[\s-]?)?[6-9]\d{4}[\s-]?\d{5}|\d{11,13})(?![\d-])',
  );
  static final _money = RegExp(
    r'(₹\s*\d[\d,.]*|\b(rs\.?|inr)\s*\d[\d,.]*|\d[\d,.]*\s*(rs|rupees?|rupaai|rupai|ரூபாய்|ரூ)\b)',
    caseSensitive: false,
  );
  static const _secretKeys = {
    'phone',
    'mobile',
    'email',
    'upi',
    'balance',
    'due',
    'amount',
    'money',
    'price',
    'whatsapp',
  };

  String alias(String person) =>
      _aliases.putIfAbsent(person, () => 'person_${_aliases.length + 1}');

  String text(String input) {
    var s = input
        .replaceAll(_email, '[email]')
        .replaceAll(_money, '[money]')
        .replaceAll(_phone, '[phone]');
    if (hideNames) {
      for (final person in _people) {
        final pattern = RegExp(
          '(?<![\\p{L}\\p{M}])${RegExp.escape(person)}',
          caseSensitive: false,
          unicode: true,
        );
        s = s.replaceAllMapped(pattern, (_) => alias(person));
      }
    }
    return s;
  }

  Object? value(Object? v) {
    if (v is String) return text(v);
    if (v is Map) {
      return {
        for (final e in v.entries)
          if (!_secretKeys.contains('${e.key}'.toLowerCase()))
            '${e.key}': value(e.value),
      };
    }
    if (v is List) return v.map(value).toList();
    return v;
  }
}

// --- the report ---------------------------------------------------------------------

String reportStamp(DateTime t) =>
    '${t.year}${_two(t.month)}${_two(t.day)}_${_two(t.hour)}${_two(t.minute)}';
String _two(int n) => n.toString().padLeft(2, '0');

/// The whole report as JSON-ready data.
Map<String, Object?> buildVoiceReport({
  required List<VoiceEvent> events,
  Map<String, Object?> device = const {},
  List<VoiceTestResult> selfTest = const [],
  List<LiveTestResult> live = const [],
  bool hideNames = true,
  Iterable<String> people = const [],
  Iterable<String> cows = const [],
  DateTime? now,
}) {
  final scrub = ReportScrubber(hideNames: hideNames, people: people);
  final created = now ?? DateTime.now();
  final failures = selfTest.where((r) => !r.passed).toList();
  final errors = events.where(
    (e) => e.type.contains('error') || e.type.contains('denied'),
  );
  final counts = <String, int>{};
  for (final e in events) {
    counts[e.type] = (counts[e.type] ?? 0) + 1;
  }
  return {
    'header': voiceReportHeader,
    'schemaVersion': voiceReportSchemaVersion,
    'createdAt': created.toIso8601String(),
    'appVersion': vimoAppVersion,
    'privacy': {'namesHidden': hideNames},
    'device': scrub.value(device),
    'cows': cows.toList(),
    'summary': {
      'events': events.length,
      'eventTypes': counts,
      'errors': errors.length,
      'selfTest': {
        'total': selfTest.length,
        'passed': selfTest.length - failures.length,
        'failed': failures.length,
      },
      'liveTest': {
        'total': live.length,
        'matched': live.where((l) => l.matched).length,
        'markedWrong': live.where((l) => l.ownerSaysRight == false).length,
      },
    },
    'selfTestFailures': scrub.value([for (final f in failures) f.toJson()]),
    'liveTest': scrub.value([for (final l in live) l.toJson()]),
    'events': scrub.value([for (final e in events) e.toJson()]),
  };
}

/// The same report for people: summary first, then failures, then the log.
String voiceReportMarkdown(Map<String, Object?> report) {
  final b = StringBuffer();
  final summary = (report['summary'] as Map?) ?? const {};
  final self = (summary['selfTest'] as Map?) ?? const {};
  final live = (summary['liveTest'] as Map?) ?? const {};
  b
    ..writeln('# VIMO voice report')
    ..writeln()
    ..writeln(report['header'])
    ..writeln()
    ..writeln('- Schema version: ${report['schemaVersion']}')
    ..writeln('- Created: ${report['createdAt']}')
    ..writeln('- App version: ${report['appVersion']}')
    ..writeln(
      '- Names hidden: ${((report['privacy'] as Map?) ?? const {})['namesHidden']}',
    )
    ..writeln();
  b.writeln('## Summary');
  b.writeln();
  b.writeln(
    '- Self-test: ${self['passed'] ?? 0} of ${self['total'] ?? 0} passed, '
    '${self['failed'] ?? 0} failed',
  );
  b.writeln(
    '- Live mic test: ${live['matched'] ?? 0} of ${live['total'] ?? 0} '
    'understood, ${live['markedWrong'] ?? 0} marked wrong by the owner',
  );
  b.writeln(
    '- Events logged: ${summary['events'] ?? 0}, errors: ${summary['errors'] ?? 0}',
  );
  final device = (report['device'] as Map?) ?? const {};
  if (device.isNotEmpty) {
    b.writeln();
    b.writeln('## Device');
    b.writeln();
    for (final e in device.entries) {
      b.writeln('- ${e.key}: ${e.value}');
    }
  }
  final failures = (report['selfTestFailures'] as List?) ?? const [];
  b.writeln();
  b.writeln('## Self-test failures (${failures.length})');
  b.writeln();
  if (failures.isEmpty) b.writeln('None.');
  for (final f in failures.whereType<Map>()) {
    b.writeln(
      '- "${f['text']}": expected ${jsonEncode(f['expected'])}, '
      'got ${jsonEncode(f['got'])}',
    );
  }
  final liveRows = (report['liveTest'] as List?) ?? const [];
  if (liveRows.isNotEmpty) {
    b.writeln();
    b.writeln('## Live mic test');
    b.writeln();
    for (final l in liveRows.whereType<Map>()) {
      final verdict = switch (l['ownerSaysRight']) {
        true => 'right',
        false => 'WRONG',
        _ => 'not marked',
      };
      b.writeln(
        '- Read "${l['prompt']}", heard "${l['heard']}" '
        '(confidence ${l['confidence'] ?? '-'}), understood '
        '${jsonEncode(l['understood'])}, $verdict'
        '${'${l['correction'] ?? ''}'.isEmpty ? '' : ', owner says: "${l['correction']}"'}',
      );
    }
  }
  final events = (report['events'] as List?) ?? const [];
  b.writeln();
  b.writeln('## Event log (${events.length})');
  b.writeln();
  b.writeln('```');
  for (final e in events.whereType<Map>()) {
    b.writeln('${e['t']} ${e['type']} ${jsonEncode(e['d'])}');
  }
  b.writeln('```');
  return b.toString();
}
