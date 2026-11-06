import 'package:flutter_test/flutter_test.dart';
import 'package:ranch_management/voice_parser.dart';
import 'package:ranch_management/voice_understanding.dart';

/// Sentences as Whisper large-v3 wrote the owner's own recordings, and what
/// they mean.
void main() {
  const cows = ['Maina', 'Shalanga', 'Valliyamma', 'Karupalazhi'];
  const aliases = {
    'Shalanga': ['ஷலங்கா'],
    'Valliyamma': ['வல்லியம்மா'],
    'Karupalazhi': ['கருபலழி'],
    'Maina': ['மைனா'],
  };
  ({String intent, Map<String, Object?> slots}) read(String t) =>
      understandVoice(t, cows: cows, aliases: aliases);

  test('pregnancy heard as "சினை உருதியானது"', () {
    final r = read('வல்லியமா சனை உருதியானது.');
    expect(r.intent, 'pregnancy_confirmed');
    expect(r.slots['cow'], 'Valliyamma');
    expect(read('சலங்கை, சன உருதியாவிட்டது.').intent, 'pregnancy_confirmed');
  });

  test('limping heard as "நொந்துது"', () {
    final r = read('மைநா மாடு நொந்துது');
    expect(r.intent, 'symptom');
    expect(r.slots['symptoms'], ['limping']);
  });

  test('injection heard as "ஊஷி"', () {
    expect(read('மயினா மாட்டுக்கு ஊஷி போட்டேன்.').intent, 'vaccination');
  });

  test('litres glued or misspelt still count', () {
    expect(
      read('நேற்று மாலை செவந்தி பத்திலிட்டர் கொடுத்துச்சி').slots['liters'],
      10,
    );
    expect(read('ஹே விமோ, சோம்பேரி ஆர்லிட்டர்').slots['liters'], 6);
    expect(
      read('இன்று காலை வள்ளியம்மா 5 லைட்டர் பால் கொடுத்தது').slots['liters'],
      5,
    );
  });

  test('"நேர்த்து மாலை" is yesterday evening', () {
    final r = read('நேர்த்து மாலை சலங்க பத்து லிட்டர் கொடுத்தச்சு');
    expect(r.slots['date'], 'yesterday');
    expect(r.slots['session'], 'Evening');
    expect(r.slots['liters'], 10);
  });

  test('"ஆடு" is "add" only before "பண்ணு"', () {
    expect(voiceTokens('கரப்பலைக்கு 3 லிட்டர் அடு பண்ணு'), contains('add'));
    expect(voiceTokens('ஆடு வாங்கினேன்'), contains('ஆடு'));
    expect(voiceTokens('ஆர் வந்தாங்க'), contains('ஆர்'));
  });

  test('"twenty five kilos" is 25', () {
    expect(read('bought twenty five kilos of bran').slots['qty'], 25);
  });
}
