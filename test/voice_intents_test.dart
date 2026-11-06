import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ranch_management/voice_diagnostics.dart';
import 'package:ranch_management/voice_understanding.dart';

/// The owner's labelled sample sentences (train + test sets, 24k) as a
/// benchmark for every intent, not only milk.
const cows = [
  'Bhavani', 'Gowri', 'Kalyani', 'Karuppi', 'Kaveri', 'Komathi', 'Lakshmi',
  'Madhavi', 'Mayil', 'Nandhini', 'Parvathi', 'Poongodi', 'Rani', 'Sevalai',
  'Sevalla', 'Sivappi', 'Thanga', 'Vellachi', 'Vellaiyamma',
];

void main() {
  final file = File('test/data/voice_intent_samples.jsonl');
  final rows = file
      .readAsLinesSync()
      .where((l) => l.trim().isNotEmpty)
      .map((l) => jsonDecode(l) as Map<String, dynamic>)
      .toList();
  final verbose = Platform.environment['VOICE_REPORT'] == '1';

  test('every intent of the sample sentences', () {
    final byIntent = <String, List<int>>{};
    final misses = <String, List<String>>{};
    for (final row in rows) {
      final out = Map<String, dynamic>.from(row['output'] as Map);
      final want = '${out['action']}';
      final got = understandVoice('${row['input']}', cows: cows);
      final counts = byIntent.putIfAbsent(want, () => [0, 0]);
      counts[1]++;
      if (got.intent == want) {
        counts[0]++;
      } else {
        final list = misses.putIfAbsent(want, () => []);
        if (list.length < 25) list.add('${row['input']}  =>  ${got.intent} ${jsonEncode(got.slots)}');
      }
    }
    var good = 0;
    var total = 0;
    for (final e in byIntent.entries) {
      good += e.value[0];
      total += e.value[1];
      // ignore: avoid_print
      print('${e.key}: ${e.value[0]} / ${e.value[1]} = '
          '${(100 * e.value[0] / e.value[1]).toStringAsFixed(1)}%');
      if (verbose) {
        for (final m in misses[e.key] ?? const []) {
          // ignore: avoid_print
          print('    miss: $m');
        }
      }
    }
    // ignore: avoid_print
    print('ALL: $good / $total = ${(100 * good / total).toStringAsFixed(1)}%');
    expect(good / total, greaterThan(.9));
  });

  test('key slots of the main intents', () {
    final checked = <String, List<int>>{};
    for (final row in rows) {
      final out = Map<String, dynamic>.from(row['output'] as Map);
      final want = '${out['action']}';
      const keys = {
        'expense': ['amount'],
        'stock_use': ['item', 'qty'],
        'stock_in': ['item', 'qty'],
        'add_cow': ['amount', 'breed'],
        'vet_visit': ['fee'],
        'sell_milk': ['liters'],
        'payment': ['amount'],
        'calf_birth': ['gender'],
        'vaccination': ['vaccine'],
      };
      final slotKeys = keys[want];
      if (slotKeys == null) continue;
      final got = understandVoice('${row['input']}', cows: cows);
      if (got.intent != want) continue;
      final expected = {for (final k in slotKeys) k: out[k]};
      final c = checked.putIfAbsent(want, () => [0, 0]);
      c[1]++;
      if (slotsMatch(expected, got.slots)) c[0]++;
    }
    for (final e in checked.entries) {
      // ignore: avoid_print
      print('slots ${e.key}: ${e.value[0]} / ${e.value[1]}');
      expect(e.value[0] / e.value[1], greaterThan(.85), reason: e.key);
    }
  });
}
