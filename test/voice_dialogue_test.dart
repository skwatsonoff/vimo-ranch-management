import 'package:flutter_test/flutter_test.dart';
import 'package:ranch_management/voice_dialogue.dart';
import 'package:ranch_management/voice_parser.dart';
import 'package:ranch_management/voice_understanding.dart';

void main() {
  const cows = ['Lakshmi', 'Kaveri'];
  VoiceDialogue dialogue() => VoiceDialogue(cows: () => cows);
  DialogueTurn reply(VoiceDialogue d, String text) {
    final c = parseVoiceCommand(text, cows);
    return d.answer(text, yes: c.yes, no: c.no);
  }

  test('"Luna nu pudhu maadu vaangunom": profile, photo, age, breed', () {
    final d = dialogue();
    const text = 'Luna nu pudhu maadu vaangunom';
    final reading = understandVoice(text, cows: cows);
    expect(reading.intent, 'add_cow');
    expect(reading.slots['name'], 'luna');

    var turn = d.start(reading, text);
    expect(turn.say!.ta, contains('புதிய profile உருவாக்கவா'));
    expect(turn.say!.en, 'Shall I create a profile for luna?');

    turn = reply(d, 'ஆமா');
    expect(d.asking, 'photo');
    expect(turn.say!.ta, contains('புகைப்படம்'));

    turn = reply(d, 'இல்ல');
    expect(d.asking, 'age_months');
    expect(turn.say!.ta, contains('எத்தனை மாத வயசு'));

    turn = reply(d, 'ரெண்டு வருஷம்');
    expect(d.asking, 'breed');

    turn = reply(d, 'ஜெர்சி');
    expect(turn.finished, isTrue);
    expect(turn.action!.kind, 'add_cow');
    expect(turn.action!.data['name'], 'luna');
    expect(turn.action!.data['age_months'], 24);
    expect(turn.action!.data['breed'], 'jersey');
    expect(turn.action!.data['photoWanted'], isFalse);
    expect(turn.say!.ta, contains('profile உருவாக்கினேன்'));
    expect(d.active, isFalse);
  });

  test('a missing amount is asked for, then confirmed', () {
    final d = dialogue();
    const text = 'kayiru selavu';
    final reading = understandVoice(text, cows: cows);
    expect(reading.intent, 'expense');
    var turn = d.start(reading, text);
    expect(d.asking, 'amount');
    expect(turn.say!.ta, 'எவ்வளவு ரூபாய்?');
    turn = reply(d, '150 ரூபாய்');
    expect(d.asking, 'confirm');
    expect(turn.say!.ta, contains('150 ரூபாய் செலவு. சேர்க்கவா?'));
    turn = reply(d, 'சரி');
    expect(turn.action!.kind, 'expense');
    expect(turn.action!.data['amount'], 150);
  });

  test('"no" at the confirmation drops the entry', () {
    final d = dialogue();
    const text = 'லட்சுமிக்கு ஊசி போட்டேன்';
    final turn0 = d.start(understandVoice(text, cows: cows), text);
    expect(turn0.say!.ta, contains('ஊசி போட்டது. சேர்க்கவா?'));
    final turn = reply(d, 'வேண்டாம்');
    expect(turn.finished, isTrue);
    expect(turn.action, isNull);
    expect(d.active, isFalse);
  });

  test('an answer VIMO did not get repeats the question politely', () {
    final d = dialogue();
    const text = 'doctor vandhaaru';
    d.start(understandVoice(text, cows: cows), text);
    expect(d.asking, 'cow');
    final turn = reply(d, 'ம்ம்');
    expect(d.asking, 'cow');
    expect(turn.say!.ta, startsWith('புரியல.'));
    reply(d, 'காவேரி');
    expect(d.asking, 'amount');
  });

  test('questions are answered at once, not confirmed', () {
    final d = dialogue();
    const text = 'இன்று எவ்வளவு பால்?';
    final reading = understandVoice(text, cows: cows);
    expect(reading.intent, 'query');
    final turn = d.start(reading, text);
    expect(turn.action!.kind, 'query');
    expect(turn.action!.data['metric'], 'milk');
    expect(turn.finished, isTrue);
  });

  test('sales of cows and payments are left to their own screens', () {
    final d = dialogue();
    const text = 'kaveri maaduva 30000 rupaaiku vitten';
    final turn = d.start(understandVoice(text, cows: cows), text);
    expect(turn.action, isNull);
    expect(turn.say!.ta, contains('Sell'));
  });

  test('Tamil numbers up to a hundred', () {
    expect(extractLitres(voiceTokens('இருபத்தி ஐந்து லிட்டர்')), 25);
    expect(extractLitres(voiceTokens('irubathi anju litre')), 25);
    expect(extractLitres(voiceTokens('முப்பது')), 30);
    expect(extractLitres(voiceTokens('முக்கால் லிட்டர்')), .75);
    expect(extractLitres(voiceTokens('onnara litre')), 1.5);
    expect(amountsIn(voiceTokens('ஐநூறு ரூபாய்')), [500]);
    expect(amountsIn(voiceTokens('rendu aayiram')), [2000]);
  });

  test('a correction changes the next understanding of the same words', () {
    const ranch = ['Maina', 'Lakshmi'];
    final lexicon = VoiceLexicon();
    // VIMO heard "மீன்" (fish) when the owner said "மைனா".
    expect(
      understandVoice('மீன் 5 லிட்டர்', cows: ranch).slots['cow'],
      isNull,
    );
    final learned = lexicon.learn('மீன் 5 லிட்டர்', 'மைனா 5 லிட்டர்');
    expect(learned, [('மீன்', 'மைனா')]);
    // The same sentence, and the same word in a new sentence.
    final again = understandVoice(
      'மீன் 5 லிட்டர்',
      cows: ranch,
      rewrite: lexicon.apply,
    );
    expect(again.slots['cow'], 'Maina');
    final other = understandVoice(
      'நேற்று மீன் 3 லிட்டர்',
      cows: ranch,
      rewrite: lexicon.apply,
    );
    expect(other.slots['cow'], 'Maina');
    expect(other.slots['liters'], 3);
    // Numbers are never learned as words.
    expect(lexicon.learn('maina 5 litre', 'maina 6 litre'), isEmpty);
  });
}
