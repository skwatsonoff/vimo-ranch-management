import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ranch_management/voice_diagnostics.dart';
import 'package:ranch_management/voice_understanding.dart';

/// The built-in corpus the phone's self-test runs: the pass rate must stay
/// at least 90%.
void main() {
  test('voice corpus pass rate', () {
    final json =
        jsonDecode(File('assets/voice/voice_corpus.json').readAsStringSync())
            as Map<String, dynamic>;
    final cows = [for (final c in json['cows'] as List) '$c'];
    final cases = [
      for (final u in (json['utterances'] as List).whereType<Map>())
        VoiceTestCase.fromJson(Map<String, dynamic>.from(u)),
    ];
    final results = runVoiceSelfTest(
      cases,
      (t) => understandVoice(t, cows: cows),
    );
    final failed = results.where((r) => !r.passed).toList();
    final rate = (results.length - failed.length) / results.length;
    // ignore: avoid_print
    print(
      'corpus: ${results.length - failed.length} / ${results.length} = '
      '${(rate * 100).toStringAsFixed(1)}%',
    );
    for (final f in failed) {
      // ignore: avoid_print
      print('  fail: ${jsonEncode(f.toJson())}');
    }
    expect(rate, greaterThanOrEqualTo(.9));
  });
}
