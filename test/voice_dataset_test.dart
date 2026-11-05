import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ranch_management/voice_parser.dart';

/// The ranch's cows in the sample sentences.
const ranchCows = [
  'Bhavani',
  'Gowri',
  'Kalyani',
  'Karuppi',
  'Kaveri',
  'Komathi',
  'Lakshmi',
  'Madhavi',
  'Mayil',
  'Nandhini',
  'Parvathi',
  'Poongodi',
  'Rani',
  'Sevalai',
  'Sevalla',
  'Sivappi',
  'Thanga',
  'Vellachi',
  'Vellaiyamma',
];

/// Which ranch cow a sample's expected name means ("கருப்பி" is Karuppi).
String? expectedCow(String? name) {
  if (name == null) return null;
  final key = phoneticKey(name);
  String? best;
  double score = 0;
  for (final cow in ranchCows) {
    final s = soundSimilarity(key, phoneticKey(cow));
    if (s > score) {
      score = s;
      best = cow;
    }
  }
  return score >= .7 ? best : name;
}

void main() {
  final samples = File('test/data/voice_milk_samples.jsonl')
      .readAsLinesSync()
      .where((l) => l.trim().isNotEmpty)
      .map((l) => jsonDecode(l) as Map<String, dynamic>)
      .toList();
  List<Map<String, dynamic>> of(String action) =>
      samples.where((s) => (s['output'] as Map)['action'] == action).toList();
  final verbose = Platform.environment['VOICE_REPORT'] == '1';

  double check(
    String title,
    List<Map<String, dynamic>> rows,
    bool Function(VoiceCommand c, Map<String, dynamic> out) ok,
  ) {
    var good = 0;
    final misses = <String>[];
    for (final row in rows) {
      final c = parseVoiceCommand(row['input'] as String, ranchCows);
      final out = Map<String, dynamic>.from(row['output'] as Map);
      if (ok(c, out)) {
        good++;
      } else if (misses.length < 40) {
        misses.add(
          '${row['input']}  =>  cow ${c.cow} litres ${c.litres} '
          'sale ${c.sale} fix ${c.correction}  (want $out)',
        );
      }
    }
    final rate = good / rows.length;
    // ignore: avoid_print
    print(
      '$title: $good / ${rows.length} = ${(rate * 100).toStringAsFixed(1)}%',
    );
    if (verbose) {
      for (final m in misses) {
        // ignore: avoid_print
        print('   miss: $m');
      }
    }
    return rate;
  }

  test('milk entries: the right cow and litres', () {
    final rows = of('milk_record');
    final cowRate = check('cow', rows, (c, out) {
      final want = expectedCow(out['cow'] as String?);
      return want == null ? c.cow == null || !c.cowIsSure : c.cow?.name == want;
    });
    final litreRate = check('litres', rows, (c, out) {
      final want = (out['liters'] as num?)?.toDouble();
      return c.litres == want;
    });
    final notSale = check('not taken as a sale', rows, (c, _) => !c.sale);
    expect(cowRate, greaterThan(.97));
    expect(litreRate, greaterThan(.97));
    expect(notSale, greaterThan(.97));
  });

  test('milk given to people is recognised as a sale, never as milking', () {
    final rate = check('sale', of('sell_milk'), (c, _) => c.sale);
    expect(rate, greaterThan(.95));
  });

  test('corrections change the litres', () {
    final rows = of(
      'edit_last',
    ).where((r) => (r['output'] as Map).containsKey('liters'));
    final rate = check(
      'correction',
      rows.toList(),
      (c, out) => c.correction && c.litres == (out['liters'] as num).toDouble(),
    );
    expect(rate, greaterThan(.97));
  });

  test('"remove that" removes the last entry', () {
    final rate = check('delete', of('delete_last'), (c, _) => c.cancel);
    expect(rate, greaterThan(.97));
  });
}
