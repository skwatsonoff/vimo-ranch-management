/// How speech recognisers really write the owner's dairy words.
///
/// Learned from the owner's own "Train VIMO" recordings (224 sentences,
/// three speakers, heard by Whisper large-v3 and lined up with what was
/// read): "சினை உருதியானது" for "சினை உறுதி ஆனது", "நொந்துது" for
/// "நொண்டுது", "லேட்டர்" for "லிட்டர்", "நேர்த்து மாலை" for "நேத்து மாலை".
/// Each heard spelling is put back to the word VIMO knows before a
/// sentence is understood. Spellings that are real words with another
/// meaning ("ஆடு" is a goat, "ஆர்" is "who") are only changed where the
/// words around them leave no doubt.
///
/// Pure Dart, applied by `voiceTokens`; tested in
/// test/voice_heard_fixes_test.dart.
library;

/// One heard word → the word(s) VIMO knows. Never a real word with
/// another everyday meaning.
const _plain = <String, String>{
  // Pregnancy confirmed.
  'உருதி': 'உறுதி',
  'உருதியானது': 'உறுதி ஆனது',
  'உருதியான': 'உறுதி ஆனது',
  'உருதியாவிட்டது': 'உறுதி ஆனது',
  'வுருதியானது': 'உறுதி ஆனது',
  'உறுதியானது': 'உறுதி ஆனது',
  'உறுதியாவிட்டது': 'உறுதி ஆனது',
  'செனை': 'சினை',
  'சனை': 'சினை',
  'செனா': 'சினை',
  'செனே': 'சினை',
  'சினையூர்து': 'சினை',
  'யானது': 'ஆனது',
  'ஆனதை': 'ஆனது',
  // Limping.
  'நொண்டுது': 'நொண்டுகிறது',
  'நொந்துது': 'நொண்டுகிறது',
  'நொந்துக்குது': 'நொண்டுகிறது',
  'நொண்டுக்குது': 'நொண்டுகிறது',
  'நொண்டுகு': 'நொண்டுகிறது',
  'நொன்றுகிறது': 'நொண்டுகிறது',
  'நொம்புது': 'நொண்டுகிறது',
  'நுண்டுது': 'நொண்டுகிறது',
  // Injection.
  'ஊஷி': 'ஊசி',
  'கூசி': 'ஊசி',
  'உசி': 'ஊசி',
  'பொட்டேன்': 'போட்டேன்',
  'மட்டுக்கு': 'மாட்டுக்கு',
  'மாட்டக்கு': 'மாட்டுக்கு',
  // Days and times.
  'இந்து': 'இன்று',
  'தாலை': 'காலை',
  // Litres and numbers.
  'லேட்டர்': 'லிட்டர்',
  'லைட்டர்': 'லிட்டர்',
  'லீட்டர்': 'லிட்டர்',
  'லிட்டார்': 'லிட்டர்',
  'லைட்டார்': 'லிட்டர்',
  'லிட்டேர்': 'லிட்டர்',
  'டிட்டர்': 'லிட்டர்',
  'ரிட்டார்': 'லிட்டர்',
  'மூண்டு': 'மூணு',
  'மூனு': 'மூணு',
  'பண்ணண்டு': 'பன்னிரண்டு',
  'பண்ணிரண்டு': 'பன்னிரண்டு',
  'பன்னண்டு': 'பன்னிரண்டு',
  'ஒன்னரல்': 'ஒன்றரை',
  'இருவுது': 'இருபது',
  'நாப்பது': 'நாற்பது',
  'அம்பது': 'ஐம்பது',
  // Gave (milk).
  'கொடுத்துச்சி': 'கொடுத்தது',
  'கொடுத்தச்சு': 'கொடுத்தது',
  'கொடுத்துது': 'கொடுத்தது',
  'கொடுத்தசு': 'கொடுத்தது',
  'கொடுத்துச்சீன்': 'கொடுத்தது',
  'கொடுத்துகிறது': 'கொடுத்தது',
  'கொடுத்துகிறோம்': 'கொடுத்தது',
  'குடுத்தது': 'கொடுத்தது',
  'குடுத்துச்சு': 'கொடுத்தது',
  'குடுத்துச்சே': 'கொடுத்தது',
  // Money, feed and things.
  'ருபாய்': 'ரூபாய்',
  'ருபா': 'ரூபாய்',
  'சலபு': 'செலவு',
  'பெற்றோல்': 'பெட்ரோல்',
  'கைரு': 'கயிறு',
  'மைக்கோல்': 'வைக்கோல்',
  'மூட்டாய்': 'மூட்டை',
  'பயன்படுத்தினீன்': 'பயன்படுத்தினேன்',
  // Finished.
  'முடிச்சுட்டேன்': 'முடிச்சிட்டேன்',
  'புடிச்சுட்டேன்': 'முடிச்சிட்டேன்',
  'சேவ': 'save',
  'சேவு': 'save',
  // The wake word.
  'விமோம்': 'விமோ',
  'விமோஸ்': 'விமோ',
  'விம்மு': 'விமோ',
  'ஹேவிமோ': 'ஹே விமோ',
};

/// "add" as heard before "பண்ணு" ("அடு பண்ணு", "ஆடு பண்ணு").
const _addHeard = {'அடு', 'அட்', 'ஏட்', 'அட்டு', 'ஐடு', 'ஆட்', 'ஆடு', 'அட'};
const _pannuHeard = {
  'பண்ணு',
  'பண்ண',
  'பண்ணே',
  'பண்ணும்',
  'பண்ணேன்',
  'வண்ணு',
  'pannu',
};

/// "நேத்து" as heard before a time of day ("நேர்த்து மாலை").
const _yesterdayHeard = {'நேர்த்து', 'நீட்டு', 'ஏற்று', 'மேற்றும்', 'நேற்றும்'};
const _timesOfDay = {'காலை', 'மாலை', 'ராத்திரி', 'இரவு', 'kaalai', 'maalai'};

/// Numbers heard before "லிட்டர்" ("ஆர் லிட்டர்" is six litres).
const _beforeLitre = {'ஆர்': 'ஆறு', 'பத்தி': 'பத்து', 'எட்டுரி': 'எட்டு'};
const _litreWords = {'லிட்டர்', 'litre', 'liter', 'litres', 'liters'};

/// "சினை" as heard before "உறுதி" ("சன உருதியானது").
const _sinaiHeard = {'சன', 'சண', 'சனா', 'சென்னை', 'செனை', 'சனை'};

/// Words glued to "லிட்டர்" by the recogniser ("பத்திலிட்டர்").
final _gluedLitre = RegExp(
  r'^(.{2,}?)(லிட்டர்|லேட்டர்|லைட்டர்|லீட்டர்|லிட்டார்|லைட்டார்|ரிட்டார்)$',
);

/// [tokens] with heard spellings put back to the words VIMO knows.
List<String> fixHeardTokens(List<String> tokens) {
  final split = <String>[];
  for (final t in tokens) {
    final glued = _gluedLitre.firstMatch(t);
    final words = glued != null ? [glued[1]!, glued[2]!] : [t];
    for (final w in words) {
      final plain = _plain[w];
      split.addAll(plain == null ? [w] : plain.split(' '));
    }
  }
  final out = <String>[];
  for (int i = 0; i < split.length; i++) {
    final t = split[i];
    final next = i + 1 < split.length ? split[i + 1] : '';
    if (_addHeard.contains(t) && _pannuHeard.contains(next)) {
      out
        ..add('add')
        ..add('பண்ணு');
      i++;
    } else if (_yesterdayHeard.contains(t) && _timesOfDay.contains(next)) {
      out.add('நேத்து');
    } else if (_beforeLitre.containsKey(t) && _litreWords.contains(next)) {
      out.add(_beforeLitre[t]!);
    } else if (_sinaiHeard.contains(t) && next == 'உறுதி') {
      out.add('சினை');
    } else {
      out.add(t);
    }
  }
  return out;
}
