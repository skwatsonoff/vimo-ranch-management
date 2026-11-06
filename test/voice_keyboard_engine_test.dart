import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ranch_management/voice_engine.dart';
import 'package:ranch_management/voice_keyboard_engine.dart';

void main() {
  late DictationController box;
  late KeyboardDictationEngine engine;
  late List<VoiceHeard> heard;
  late List<String> statuses;
  late List<StreamSubscription<Object?>> subs;

  setUp(() async {
    box = DictationController();
    engine = KeyboardDictationEngine(
      box,
      typingPause: const Duration(milliseconds: 60),
    );
    heard = [];
    statuses = [];
    subs = [
      engine.results.listen(heard.add),
      engine.statuses.listen(statuses.add),
    ];
    await engine.start(locale: 'ta-IN');
  });

  tearDown(() async {
    for (final s in subs) {
      await s.cancel();
    }
    await engine.dispose();
    box.dispose();
  });

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('dictated words arrive as they are spoken', () async {
    box.text = 'மைனா';
    box.text = 'மைனா அஞ்சு லிட்டர்';
    await settle();
    expect(heard.map((h) => h.text), ['மைனா', 'மைனா அஞ்சு லிட்டர்']);
    expect(heard.every((h) => !h.isFinal), isTrue);
    expect(statuses, [VoiceStatus.listening]);
  });

  test('words already used are never sent again', () async {
    box.text = 'Maina 5 litre';
    await settle();
    await engine.cancel();
    expect(box.fresh, isEmpty);
    expect(statuses.last, VoiceStatus.notListening);
    await engine.start(locale: 'ta-IN');
    heard.clear();
    box.text = 'Maina 5 litre Kaveri 3 litre';
    await settle();
    expect(heard.single.text, 'Kaveri 3 litre');
  });

  test('typed letters wait for a pause, then count as one sentence', () async {
    for (final c in 'Rani 4'.split('')) {
      box.text = box.text + c;
    }
    await settle();
    expect(heard, isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(heard.single.text, 'Rani 4');
    expect(heard.single.isFinal, isTrue);
  });

  test('Return sends typed words at once', () async {
    box.text = 'R';
    box.text = 'Ra';
    box.text = 'Ran';
    engine.submit();
    await settle();
    expect(heard.single.text, 'Ran');
    expect(heard.single.isFinal, isTrue);
  });

  test(
    'words that came while VIMO was busy are sent on the next start',
    () async {
      await engine.cancel();
      box.text = 'Maina 2 litre';
      await settle();
      expect(heard, isEmpty);
      await engine.start(locale: 'ta-IN');
      await settle();
      expect(heard.single.text, 'Maina 2 litre');
    },
  );

  test('a cleared box starts afresh', () async {
    box.text = 'Maina 5';
    await engine.cancel();
    box.clear();
    expect(box.used, 0);
    await engine.start(locale: 'ta-IN');
    heard.clear();
    box.text = 'Rani 3';
    await settle();
    expect(heard.single.text, 'Rani 3');
  });
}
