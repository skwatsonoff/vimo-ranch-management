/// Understanding of spoken milk commands for VIMO's voice milk mode.
///
/// Pure Dart with no app state, so every rule here is unit tested. People
/// speak Tamil, English and Tanglish freely mixed ("மைனா 5 litre add பண்ணு",
/// "Maina add 5 litre", "hey vimo maina ku anju litre podu"), and the phone's
/// recogniser writes the same words in Tamil script or Latin letters. Every
/// word is therefore compared by sound: both scripts reduce to one phonetic
/// key, so "மைனா", "Maina" and "Mayna" are the same cow.
library;

// --- phonetic keys -------------------------------------------------------------

const _consonants = <String, String>{
  'க': 'k',
  'ங': 'n',
  'ச': 's',
  'ஞ': 'n',
  'ட': 't',
  'ண': 'n',
  'த': 't',
  'ந': 'n',
  'ப': 'p',
  'ம': 'm',
  'ய': 'y',
  'ர': 'r',
  'ல': 'l',
  'வ': 'v',
  'ழ': 'l',
  'ள': 'l',
  'ற': 'r',
  'ன': 'n',
  'ஜ': 'j',
  'ஷ': 's',
  'ஸ': 's',
  'ஶ': 's',
  'ஹ': 'h',
};

const _vowels = <String, String>{
  'அ': 'a',
  'ஆ': 'aa',
  'இ': 'i',
  'ஈ': 'ee',
  'உ': 'u',
  'ஊ': 'oo',
  'எ': 'e',
  'ஏ': 'e',
  'ஐ': 'ai',
  'ஒ': 'o',
  'ஓ': 'o',
  'ஔ': 'au',
};

const _signs = <String, String>{
  'ா': 'aa',
  'ி': 'i',
  'ீ': 'ee',
  'ு': 'u',
  'ூ': 'oo',
  'ெ': 'e',
  'ே': 'e',
  'ை': 'ai',
  'ொ': 'o',
  'ோ': 'o',
  'ௌ': 'au',
  '்': '',
};

final _tamilChar = RegExp(r'[஀-௿]');

/// Tamil script to plain Latin letters, by sound. Other text passes through.
String tamilToLatin(String input) {
  if (!_tamilChar.hasMatch(input)) return input;
  // "கௌ" may arrive as ெ + ௗ (two code points) rather than ௌ.
  input = input.replaceAll('\u0BC6\u0BD7', '\u0BCC');
  final out = StringBuffer();
  final chars = input.split('');
  for (int i = 0; i < chars.length; i++) {
    final c = chars[i];
    final consonant = _consonants[c];
    if (consonant != null) {
      out.write(consonant);
      final next = i + 1 < chars.length ? chars[i + 1] : '';
      final sign = _signs[next];
      if (sign != null) {
        out.write(sign);
        i++;
      } else {
        out.write('a'); // inherent vowel
      }
      continue;
    }
    final vowel = _vowels[c];
    if (vowel != null) {
      out.write(vowel);
      continue;
    }
    if (c == 'ஃ' || _signs.containsKey(c)) continue;
    out.write(c);
  }
  return out.toString();
}

/// A spelling-free sound key: "மைனா", "Maina" and "Mayna" all give "maina".
/// Voiced and unvoiced pairs merge (Tamil writes both with one letter), long
/// vowels shorten and doubled letters collapse.
String phoneticKey(String input) {
  var s = tamilToLatin(input.toLowerCase());
  s = s.replaceAll(RegExp(r'[^a-z]'), '');
  const digraphs = [
    ['zh', 'l'],
    ['sh', 's'],
    ['ch', 's'],
    ['th', 't'],
    ['dh', 't'],
    ['ph', 'p'],
    ['bh', 'p'],
    ['kh', 'k'],
    ['gh', 'k'],
    ['ng', 'nk'],
    ['ny', 'n'],
    ['ck', 'k'],
    ['x', 'ks'],
  ];
  for (final d in digraphs) {
    s = s.replaceAll(d[0], d[1]);
  }
  const singles = {
    'b': 'p',
    'd': 't',
    'g': 'k',
    'c': 'k',
    'q': 'k',
    'j': 's',
    'z': 's',
    'f': 'p',
    'w': 'v',
    'y': 'i',
    'h': '',
  };
  final buffer = StringBuffer();
  for (final ch in s.split('')) {
    buffer.write(singles[ch] ?? ch);
  }
  s = buffer
      .toString()
      .replaceAll('ks', 'ts')
      // "Gowri" and "கௌரி": the au sound is written ow, au or ou.
      .replaceAll('au', 'ov')
      .replaceAll('ou', 'ov')
      .replaceAll('ee', 'i')
      .replaceAll('oo', 'u')
      .replaceAll('ae', 'e');
  // Collapse runs of the same letter: "kutti" -> "kuti", "aa" -> "a".
  final collapsed = StringBuffer();
  String last = '';
  for (final ch in s.split('')) {
    if (ch != last) collapsed.write(ch);
    last = ch;
  }
  return collapsed.toString();
}

/// Edit distance between two short strings.
int levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var previous = List<int>.generate(b.length + 1, (i) => i);
  for (int i = 0; i < a.length; i++) {
    final current = List<int>.filled(b.length + 1, 0);
    current[0] = i + 1;
    for (int j = 0; j < b.length; j++) {
      final cost = a[i] == b[j] ? 0 : 1;
      current[j + 1] = [
        current[j] + 1,
        previous[j + 1] + 1,
        previous[j] + cost,
      ].reduce((x, y) => x < y ? x : y);
    }
    previous = current;
  }
  return previous[b.length];
}

/// 1.0 for the same sound, falling towards 0 as the keys differ.
double soundSimilarity(String a, String b) {
  if (a.isEmpty || b.isEmpty) return 0;
  final longest = a.length > b.length ? a.length : b.length;
  return 1 - levenshtein(a, b) / longest;
}

// --- tokens --------------------------------------------------------------------

/// Words of an utterance, lower-cased, punctuation removed. Decimal points
/// and fractions between digits survive ("2.5", "1/2").
List<String> voiceTokens(String text) {
  var s = text
      .toLowerCase()
      .replaceAll(RegExp('[\u200b-\u200d\ufeff]'), '')
      .replaceAll('½', ' 1/2 ');
  s = s.replaceAllMapped(RegExp(r'(\d),(\d)'), (m) => '${m[1]}.${m[2]}');
  // Split digits glued to words: "5litre", "5லிட்டர்", "maina5".
  s = s.replaceAllMapped(RegExp(r'(\d)([^\d\s./])'), (m) => '${m[1]} ${m[2]}');
  s = s.replaceAllMapped(RegExp(r'([^\d\s./])(\d)'), (m) => '${m[1]} ${m[2]}');
  s = s.replaceAll(RegExp(r'''[,!?;:"“”‘’()\[\]{}]'''), ' ');
  s = s.replaceAll(RegExp(r"(?<!\d)\.|\.(?!\d)"), ' ');
  s = s.replaceAll(RegExp(r"'s\b"), '');
  s = s.replaceAll("'", '');
  return s
      .split(RegExp(r'\s+'))
      .map((t) => t.replaceAll('-', '').trim())
      .where((t) => t.isNotEmpty)
      .toList();
}

// --- words ---------------------------------------------------------------------

const _unitWords = {
  'l',
  'lt',
  'ltr',
  'ltrs',
  'lit',
  'litre',
  'litres',
  'liter',
  'liters',
  'leter',
  'leeter',
  'litter',
  'litters',
  'லிட்டர்',
  'லிட்டர',
  'லீட்டர்',
  'லிட்டரு',
  'லிட்டருக்கு',
  'லி',
  'லிட்',
  'लीटर',
  'लिटर',
};

/// Tamil number words as people say and the recogniser writes them.
const _tamilNumbers = <String, double>{
  'ஒன்று': 1,
  'ஒண்ணு': 1,
  'ஒன்னு': 1,
  'ஒரு': 1,
  'இரண்டு': 2,
  'ரெண்டு': 2,
  'ரண்டு': 2,
  'மூன்று': 3,
  'மூணு': 3,
  'மூனு': 3,
  'நான்கு': 4,
  'நாலு': 4,
  'ஐந்து': 5,
  'அஞ்சு': 5,
  'அஞ்ச': 5,
  'ஆறு': 6,
  'ஏழு': 7,
  'எட்டு': 8,
  'ஒன்பது': 9,
  'ஒம்போது': 9,
  'ஒம்பது': 9,
  'பத்து': 10,
  'பதினொன்று': 11,
  'பதினொண்ணு': 11,
  'பதினொன்னு': 11,
  'பன்னிரண்டு': 12,
  'பன்னெண்டு': 12,
  'பதின்மூன்று': 13,
  'பதிமூணு': 13,
  'பதிமூனு': 13,
  'பதினான்கு': 14,
  'பதினாலு': 14,
  'பதினைந்து': 15,
  'பதினஞ்சு': 15,
  'பதினாறு': 16,
  'பதினேழு': 17,
  'பதினெட்டு': 18,
  'பத்தொன்பது': 19,
  'இருபது': 20,
  'இருவது': 20,
  // Tens up to நூறு; "இருபத்தி ஐந்து" joins a ten and a unit.
  'இருபத்தி': 20, 'இருபத்து': 20, 'முப்பது': 30, 'முப்பத்தி': 30,
  'முப்பத்து': 30, 'நாற்பது': 40, 'நாப்பது': 40, 'நாற்பத்தி': 40,
  'ஐம்பது': 50, 'அம்பது': 50, 'ஐம்பத்தி': 50, 'அறுபது': 60, 'அறுபத்தி': 60,
  'எழுபது': 70, 'எழுபத்தி': 70, 'எண்பது': 80, 'எண்பத்தி': 80,
  'தொண்ணூறு': 90, 'தொண்ணூத்தி': 90, 'நூறு': 100,
  'கால்': .25, 'முக்கால்': .75,
};

/// Latin spellings of Tamil, English and Hindi numbers.
const _latinNumbers = <String, double>{
  // English
  'zero': 0, 'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5,
  'six': 6, 'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10,
  'eleven': 11, 'twelve': 12, 'thirteen': 13, 'fourteen': 14,
  'fifteen': 15, 'sixteen': 16, 'seventeen': 17, 'eighteen': 18,
  'nineteen': 19, 'twenty': 20, 'thirty': 30, 'forty': 40, 'fifty': 50,
  // Tamil in Latin letters (Tanglish)
  'onnu': 1, 'onru': 1, 'ondru': 1, 'oru': 1,
  'rendu': 2, 'randu': 2, 'irandu': 2, 'erandu': 2, 'iranndu': 2,
  'moonu': 3, 'munu': 3, 'moondru': 3, 'moonru': 3,
  'naalu': 4, 'nalu': 4, 'naangu': 4, 'nangu': 4,
  'anju': 5, 'aanju': 5, 'ainthu': 5, 'aindhu': 5,
  'aaru': 6, 'aru': 6,
  'ezhu': 7, 'elu': 7, 'yezhu': 7, 'ezu': 7,
  'ettu': 8, 'yettu': 8,
  'onbathu': 9, 'onbadhu': 9, 'ombodhu': 9, 'ombothu': 9, 'ombadhu': 9,
  'pathu': 10, 'padhu': 10, 'pattu': 10, 'paththu': 10, 'patthu': 10,
  'pathinonnu': 11, 'pannendu': 12, 'pannirendu': 12,
  'pathimoonu': 13, 'pathinaalu': 14, 'pathinanju': 15,
  'pathinaaru': 16, 'pathinezhu': 17, 'pathinettu': 18,
  'irubathu': 20, 'iruvathu': 20, 'irubathi': 20, 'iruvathi': 20,
  'mupathu': 30, 'muppathu': 30, 'muppathi': 30, 'naarpathu': 40,
  'narpathu': 40, 'naapathu': 40, 'aimbathu': 50, 'ambathu': 50,
  'arubathu': 60, 'ezhubathu': 70, 'enbathu': 80, 'thonnooru': 90,
  'nooru': 100, 'hundred': 100, 'sixty': 60, 'seventy': 70, 'eighty': 80,
  'ninety': 90, 'kaal': .25, 'mukkaal': .75, 'mukkal': .75,
  // Hindi in Latin letters
  'ek': 1, 'do': 2, 'teen': 3, 'tin': 3, 'char': 4, 'chaar': 4,
  'paanch': 5, 'panch': 5, 'paach': 5, 'chhe': 6, 'chhah': 6, 'che': 6,
  'saat': 7, 'sat': 7, 'aath': 8, 'aat': 8, 'nau': 9, 'das': 10,
  'gyarah': 11, 'barah': 12, 'pandrah': 15, 'bees': 20,
  'dedh': 1.5, 'derh': 1.5, 'dhai': 2.5, 'dhaai': 2.5, 'adhai': 2.5,
};

/// Hindi in Devanagari.
const _devanagariNumbers = <String, double>{
  'एक': 1,
  'दो': 2,
  'तीन': 3,
  'चार': 4,
  'पांच': 5,
  'पाँच': 5,
  'छह': 6,
  'छः': 6,
  'छे': 6,
  'सात': 7,
  'आठ': 8,
  'नौ': 9,
  'दस': 10,
  'ग्यारह': 11,
  'बारह': 12,
  'पंद्रह': 15,
  'बीस': 20,
  'डेढ़': 1.5,
  'डेढ': 1.5,
  'ढाई': 2.5,
};

/// Words that only add a fraction: "அஞ்சு அரை", "five and a half".
const _halfWords = {'அரை', 'arai', 'ara', 'half', 'haf', 'aadha', 'आधा', '1/2'};
const _quarterWords = {'கால்', 'quarter', 'paav', 'पाव', '1/4'};
const _threeQuarterWords = {'முக்கால்', 'mukkal', 'mukkaal', '3/4'};
const _pointWords = {'point', 'புள்ளி', 'pulli', 'பாயிண்ட்', 'பாய்ண்ட்'};
const _plusHalfWords = {'saadhe', 'sadhe', 'saade', 'साढ़े', 'साढे'};
const _articleWords = {'ஒரு', 'oru', 'a', 'an'};
const _joinWords = {'and', 'n', 'um', 'a', 'மற்றும்', 'அண்ட்', 'aur', 'और'};

/// Words that carry the command but are never part of a cow's name.
const _commandWords = {
  'add', 'pannu', 'pannunga', 'pannidu', 'podu', 'pottu', 'podunga', 'milk',
  'paal', 'paalu', 'entry', 'record', 'enter', 'write', 'save', 'for', 'to',
  'the', 'is', 'of', 'please', 'pls', 'cow', 'maadu', 'maatukku', 'ku', 'kku',
  'ko', 'ke', 'ki', 'ka', 'la', 'le', 'hey', 'hi', 'ok', 'okay', 'now',
  'morning', 'evening', 'kaalai', 'maalai', 'doodh',
  'ஆட்', 'பண்ணு', 'பண்ணுங்க', 'பண்ணிடு', 'போடு', 'போட்டு', 'போடுங்க', 'சேர்',
  'சேர்த்து', 'சேரு', 'சேர்க்கவும்', 'பால்', 'பாலு', 'மாடு', 'மாட்டுக்கு', 'கு',
  'க்கு', 'எழுது', 'இன்னைக்கு', 'இன்று', 'காலை', 'மாலை', 'ஹே', 'ஹாய்', 'ஏய்',
  'ஹேய்', 'दूध', 'गाय', 'को', 'के', 'डालो', 'जोड़ो',
  'sir', 'ஐயா', 'aiya', 'ayya', 'சரியா', 'sariya', 'sollu', 'சொல்லு',
  'innaiku', 'inniki', 'innikku', 'indru', 'inaiku', 'இன்னிக்கு', 'today',
  'total', 'மொத்தம்', 'motham', 'mottham', 'gave', 'from', 'litres', 'i',
  'anna', 'akka', 'அண்ணா', 'அக்கா', 'my', 'we', 'it', 'that', 'this', 'got',
  'enga', 'en', 'oda', 'nu', 'என்று', 'எனக்கு', 'நான்',
  // "கடைசி பதிவை நீக்கு", "ippo potta pathivai azhi", "adha azhichidu"
  'pathivai', 'pathivu', 'pathivugal', 'பதிவை', 'பதிவு', 'kadaisi',
  'kadaisiya', 'கடைசி', 'கடைசியா', 'potta', 'potathai', 'pottathai', 'ippo',
  'adha', 'athai', 'adhai', 'அதை', 'அந்த', 'entry-ஐ', 'last', 'செய்', 'sei',
};

const _yesWords = {
  'yes',
  'yeah',
  'yea',
  'yep',
  'yup',
  'ya',
  'ok',
  'okay',
  'okey',
  'okk',
  'sure',
  'correct',
  'right',
  'confirm',
  'haan',
  'han',
  'haa',
  'ha',
  'ji',
  'theek',
  'thik',
  'sari',
  'seri',
  'saringa',
  'aama',
  'ama',
  'aamaa',
  'aamam',
  'amam',
  'aaama',
  'podu',
  'pottu',
  'pannu',
  'add',
  'ஆமா',
  'ஆமாம்',
  'ஆம்',
  'ஆமாங்க',
  'ஆமாம',
  'சரி',
  'சரிங்க',
  'ஓகே',
  'ஓக்கே',
  'போடு',
  'போட்டு',
  'பண்ணு',
  'ஆட்',
  'கரெக்ட்',
  'எஸ்',
  'யெஸ்',
  'சேர்',
  'சேரு',
  'हाँ',
  'हां',
  'हा',
  'ठीक',
  'जी',
  'ओके',
};

const _noWords = {
  'no',
  'nope',
  'nah',
  'not',
  'wrong',
  'illa',
  'illai',
  'ille',
  'ilai',
  'venam',
  'vendam',
  'vendaam',
  'venaam',
  'venda',
  'nahi',
  'nahin',
  'galat',
  'thappu',
  'tappu',
  'இல்ல',
  'இல்லை',
  'இல்லே',
  'இல்லீங்க',
  'வேணாம்',
  'வேண்டாம்',
  'வேண்டா',
  'தப்பு',
  'தவறு',
  'நோ',
  'नहीं',
  'नही',
  'ना',
  'गलत',
};

const _cancelWords = {
  'neekku',
  'neeku',
  'nikku',
  'azhi',
  'azhichidu',
  'azhichudu',
  'alichidu',
  'ரத்து',
  'நீக்கவும்',
  'அழிக்கவும்',
  'cancel',
  'undo',
  'delete',
  'remove',
  'erase',
  'கேன்சல்',
  'அழி',
  'அழிச்சிடு',
  'அழிச்சுடு',
  'நீக்கு',
  'நீக்கிடு',
  'hatao',
  'हटाओ',
  'mitao',
};

const _finishWords = {
  'finish',
  'finished',
  'done',
  'complete',
  'completed',
  'stop',
  'end',
  'over',
  'bas',
  'khatam',
  'khatm',
  'khattam',
  'pothum',
  'podhum',
  'pothu',
  'niruthu',
  'nirutthu',
  'போதும்',
  'நிறுத்து',
  'நிறுத்திடு',
  'ஸ்டாப்',
  'பினிஷ்',
  'ஃபினிஷ்',
  'கம்ப்ளீட்',
  'खत्म',
  'ख़त्म',
  'बस',
};

bool _isUnit(String token) => _unitWords.contains(token);

/// "X இல்லை Y": the amount after these words replaces the one before.
const _correctionWords = {
  'illa',
  'illai',
  'ille',
  'not',
  'no',
  'thappu',
  'tappu',
  'இல்லை',
  'இல்ல',
  'இல்லே',
  'தப்பு',
  'தவறு',
  'नहीं',
  'नही',
};

/// "2 litre nu maathu", "4 litre என்று மாற்று", "change it to 3".
const _changeWords = {
  'maathu',
  'maaththu',
  'mathu',
  'maatru',
  'change',
  'correct',
  'மாற்று',
  'மாத்து',
  'மாத்திடு',
  'மாற்றவும்',
  'बदलो',
};

/// Milk that went to a person: sold, given, bought or taken away.
const _saleWords = {
  'sold',
  'sell',
  'selling',
  'sale',
  'bought',
  'buy',
  'took',
  'taken',
  'kuduthen',
  'koduthen',
  'koduthaen',
  'kuduthaen',
  'kudutthen',
  'kuduthean',
  'vitten',
  'vithen',
  'vittaen',
  'vikkiren',
  'vithaen',
  'vaanginaar',
  'vaanginar',
  'vaangunaaru',
  'vaanginaaru',
  'vaangunaar',
  'vaangitu',
  'vaangittu',
  'vaangikittu',
  'poitaaru',
  'ponaaru',
  'ponaar',
  'கொடுத்தேன்',
  'குடுத்தேன்',
  'கொடுத்தோம்',
  'விற்றேன்',
  'வித்தேன்',
  'விற்பனை',
  'விற்றோம்',
  'வாங்கினார்',
  'வாங்கினாங்க',
  'வாங்கினாள்',
  'வாங்கிட்டு',
  'வாங்கிட்டார்',
  'போனார்',
  'போனாங்க',
  'बेचा',
  'दिया',
  'खरीदा',
};

/// Milk the cow gave or the person milked: never a sale.
const _milkingWords = {
  'milked',
  'karanthen',
  'karandhen',
  'karanthom',
  'kuduthuchu',
  'kuduthaa',
  'koduthuchu',
  'kudutha',
  'kedaichuchu',
  'kidaichathu',
  'கறந்தேன்',
  'கறந்தோம்',
  'கறந்தது',
  'கொடுத்தது',
  'கொடுத்தாள்',
  'குடுத்துச்சு',
  'கொடுத்துச்சு',
  'கிடைத்தது',
  'கிடைச்சது',
  'மாடு',
  'maadu',
  'cow',
};

const _morningWords = {
  'morning',
  'kaalai',
  'kalai',
  'kaalaila',
  'kaalaiyila',
  'kaalaiyil',
  'காலை',
  'காலையில',
  'காலையில்',
  'காலைல',
  'सुबह',
};
const _eveningWords = {
  'evening',
  'night',
  'maalai',
  'malai',
  'maalaila',
  'saayangaalam',
  'sayangalam',
  'raathiri',
  'மாலை',
  'மாலையில்',
  'மாலைல',
  'சாயங்காலம்',
  'ராத்திரி',
  'இரவு',
  'शाम',
  'रात',
};
const _yesterdayWords = {
  'yesterday',
  'netru',
  'nethu',
  'neththu',
  'nethiku',
  'நேற்று',
  'நேத்து',
  'नेत्रु',
  'कल',
};

/// A whole Tamil number word, also when "அரை" is fused on ("ரெண்டரை" 2.5) or a
/// unit is glued to it ("அஞ்சுலிட்டர்").
double? _tamilNumber(String token) {
  final exact = _tamilNumbers[token];
  if (exact != null) return exact;
  for (final entry in _tamilNumbers.entries) {
    final word = entry.key;
    final stem = word.endsWith('ு') ? word.substring(0, word.length - 1) : word;
    // ரெண்டரை, அஞ்சரை, ஒன்றரை, மூணரை…
    if (token == '$stemரை') return entry.value + .5;
    for (final unit in const ['லிட்டர்', 'லி']) {
      if (token == '$word$unit' || token == '$stem$unit') return entry.value;
    }
  }
  return null;
}

/// Latin Tanglish fused half: "rendara", "anjarai", "onnara".
double? _latinFusedHalf(String token) {
  for (final suffix in const ['arai', 'ara', 'rai']) {
    if (!token.endsWith(suffix) || token.length <= suffix.length + 1) continue;
    final stem = token.substring(0, token.length - suffix.length);
    for (final entry in _latinNumbers.entries) {
      final word = entry.key;
      if (word.length < 3) continue;
      final trimmed = word.endsWith('u')
          ? word.substring(0, word.length - 1)
          : word;
      if (stem == word || stem == trimmed) return entry.value + .5;
    }
  }
  return null;
}

double? _numberValue(String token) {
  final digits = double.tryParse(token);
  if (digits != null && digits.isFinite) return digits;
  return _tamilNumber(token) ??
      _latinNumbers[token] ??
      _devanagariNumbers[token] ??
      _latinFusedHalf(token);
}

double? _fractionValue(String token) {
  if (_halfWords.contains(token)) return .5;
  if (_quarterWords.contains(token)) return .25;
  if (_threeQuarterWords.contains(token)) return .75;
  return null;
}

class _NumberHit {
  double value;
  final int start;
  int end;
  final bool article;
  _NumberHit(this.value, this.start, this.end, {this.article = false});
}

/// The litres spoken in [tokens] (ignoring [skip], the cow name), and whether
/// the sentence corrects an earlier amount.
({double? value, bool correction}) readLitres(
  List<String> tokens, {
  Set<int> skip = const {},
}) {
  final hits = <_NumberHit>[];
  bool plusHalfNext = false;
  for (int i = 0; i < tokens.length; i++) {
    if (skip.contains(i)) continue;
    final t = tokens[i];
    if (_plusHalfWords.contains(t)) {
      plusHalfNext = true;
      continue;
    }
    final last = hits.isEmpty ? null : hits.last;
    // Only joining words between the last number and this one:
    // "five and a half", "அஞ்சு அரை".
    var adjacent = last != null && last.end < i;
    if (last != null) {
      for (int k = last.end + 1; k < i; k++) {
        if (!_joinWords.contains(tokens[k])) adjacent = false;
      }
    }
    // "five point five", "அஞ்சு புள்ளி அஞ்சு"
    if (_pointWords.contains(t) && last != null && last.end == i - 1) {
      if (i + 1 < tokens.length) {
        final next = _numberValue(tokens[i + 1]);
        if (next != null && next >= 0 && next < 10 && next % 1 == 0) {
          last.value = last.value.floorToDouble() + next / 10;
          last.end = i + 1;
          i++;
          continue;
        }
      }
    }
    final fraction = _fractionValue(t);
    if (fraction != null) {
      if (adjacent && last != null && last.value % 1 == 0) {
        last.value += fraction;
        last.end = i;
      } else {
        hits.add(_NumberHit(fraction, i, i));
      }
      continue;
    }
    final value = _numberValue(t);
    if (value == null) continue;
    // "twenty two"
    if (adjacent &&
        last != null &&
        last.value >= 20 &&
        last.value % 10 == 0 &&
        value < 10 &&
        last.end == i - 1) {
      last.value += value;
      last.end = i;
      continue;
    }
    hits.add(
      _NumberHit(
        value + (plusHalfNext ? .5 : 0),
        i,
        i,
        article: _articleWords.contains(t),
      ),
    );
    plusHalfNext = false;
  }
  if (hits.isEmpty) {
    return (value: null, correction: _anyWord(tokens, _changeWords));
  }
  // "ஒரு அஞ்சு லிட்டர்" means "about five litres": the article is not a number.
  final real = hits.where((h) => !h.article).toList();
  final pool = real.isEmpty ? hits : real;
  // "5 இல்லை 9 லிட்டர்", "9 illa 10 litre", "not 1, 9 litres": the number
  // after the "no" is the right one.
  for (int k = 0; k + 1 < pool.length; k++) {
    for (int t = pool[k].end + 1; t < pool[k + 1].start; t++) {
      if (_correctionWords.contains(tokens[t])) {
        return (value: pool[k + 1].value, correction: true);
      }
    }
  }
  if (pool.length > 1 && pool.first.start > 0) {
    final before = tokens[pool.first.start - 1];
    if (before == 'not' || before == 'no') {
      return (value: pool[1].value, correction: true);
    }
  }
  final change = _anyWord(tokens, _changeWords);
  for (final hit in pool) {
    final next = hit.end + 1;
    if (next < tokens.length && _isUnit(tokens[next])) {
      return (value: hit.value, correction: change);
    }
  }
  return (value: pool.last.value, correction: change);
}

/// The litres spoken in [tokens], ignoring tokens in [skip] (the cow name).
double? extractLitres(List<String> tokens, {Set<int> skip = const {}}) =>
    readLitres(tokens, skip: skip).value;

// --- cows ----------------------------------------------------------------------

/// One cow the utterance may name, with how sure the match is (0..1).
class CowGuess {
  final String name;
  final double score;
  final Set<int> tokens;
  const CowGuess(this.name, this.score, this.tokens);

  @override
  String toString() => '$name (${score.toStringAsFixed(2)})';
}

/// Case endings Tamil and Hindi put on a name: மைனாக்கு, மைனாவுக்கு, maina ko.
const _caseSuffixKeys = [
  'vuku',
  'uku',
  'iku',
  'ku',
  'kita',
  'kite',
  'vota',
  'ota',
  'vote',
  'ote',
  'vai',
  'ai',
  'ke',
  'ko',
  'ka',
  'vu',
];

double _nameScore(String candidateKey, String nameKey) {
  if (candidateKey.isEmpty || nameKey.isEmpty) return 0;
  if (candidateKey == nameKey) return 1;
  // Very short names must match exactly: "A1" is not "ah".
  if (nameKey.length <= 2) return 0;
  var best = soundSimilarity(candidateKey, nameKey);
  for (final suffix in _caseSuffixKeys) {
    if (candidateKey.endsWith(suffix) &&
        candidateKey.length - suffix.length >= 3) {
      final stem = candidateKey.substring(
        0,
        candidateKey.length - suffix.length,
      );
      final score = stem == nameKey
          ? .97
          : soundSimilarity(stem, nameKey) * .98;
      if (score > best) best = score;
    }
  }
  // A suffix the list does not know: "mainavukitta".
  if (candidateKey.startsWith(nameKey) &&
      nameKey.length >= 3 &&
      candidateKey.length - nameKey.length <= 5) {
    best = best < .92 ? .92 : best;
  }
  return best;
}

/// Every cow in [cows] scored against the words of the utterance, best first.
/// [aliases] adds other spellings of a cow's name (its Tamil or English
/// name); a match on any of them names the cow itself.
List<CowGuess> guessCows(
  List<String> tokens,
  List<String> cows, {
  Map<String, List<String>> aliases = const {},
}) {
  final guesses = <CowGuess>[];
  bool functionWord(String t) =>
      _commandWords.contains(t) ||
      _unitWords.contains(t) ||
      _yesWords.contains(t) ||
      _noWords.contains(t) ||
      _cancelWords.contains(t) ||
      _finishWords.contains(t) ||
      _halfWords.contains(t) ||
      _pointWords.contains(t) ||
      _numberValue(t) != null;
  final rawText = ' ${tokens.join(' ')} ';
  (double, Set<int>) scoreSpelling(String name) {
    final nameTokens = voiceTokens(name);
    final nameDigits = nameTokens.where((t) => double.tryParse(t) != null);
    final nameKey = phoneticKey(name);
    double best = 0;
    Set<int> bestSpan = {};
    // Exact words, as written: "Lakshmi 2" said in English.
    final lower = nameTokens.join(' ');
    if (lower.isNotEmpty && rawText.contains(' $lower ')) {
      final start = _indexOfSequence(tokens, nameTokens);
      if (start >= 0) {
        best = 1;
        bestSpan = {for (int k = 0; k < nameTokens.length; k++) start + k};
      }
    }
    if (best < 1 && nameKey.isNotEmpty) {
      final width = nameTokens.length.clamp(1, 3) + 1;
      for (int i = 0; i < tokens.length; i++) {
        if (functionWord(tokens[i])) continue;
        final keyBuffer = StringBuffer();
        for (int n = 0; n < width && i + n < tokens.length; n++) {
          final t = tokens[i + n];
          if (functionWord(t)) break;
          keyBuffer.write(phoneticKey(t));
          var score = _nameScore(keyBuffer.toString(), nameKey);
          // A two-word span must earn it: joining helps split names only.
          if (n > 0) score *= .98;
          final span = {for (int k = 0; k <= n; k++) i + k};
          if (nameDigits.isNotEmpty) {
            // "Cow 2": the number must be said right after the name.
            final after = i + n + 1;
            if (after < tokens.length && nameDigits.contains(tokens[after])) {
              span.add(after);
            } else {
              score *= .7;
            }
          }
          if (score > best) {
            best = score;
            bestSpan = span;
          }
        }
      }
    }
    return (best, bestSpan);
  }

  for (final cow in cows) {
    final name = cow.trim();
    if (name.isEmpty) continue;
    double best = 0;
    Set<int> span = {};
    for (final spelling in {name, ...?aliases[cow]}) {
      if (spelling.trim().isEmpty) continue;
      final (score, tokensUsed) = scoreSpelling(spelling.trim());
      if (score > best) {
        best = score;
        span = tokensUsed;
      }
    }
    if (best > 0) guesses.add(CowGuess(name, best, span));
  }
  guesses.sort((a, b) => b.score.compareTo(a.score));
  return guesses;
}

int _indexOfSequence(List<String> tokens, List<String> sequence) {
  if (sequence.isEmpty) return -1;
  for (int i = 0; i + sequence.length <= tokens.length; i++) {
    var all = true;
    for (int k = 0; k < sequence.length; k++) {
      if (tokens[i + k] != sequence[k]) {
        all = false;
        break;
      }
    }
    if (all) return i;
  }
  return -1;
}

// --- the command ---------------------------------------------------------------

/// How sure a cow match must be to add without asking.
const double cowSureScore = .8;

/// Below this a word is not taken as a cow at all.
const double cowMaybeScore = .62;

/// Wake word keys: "Vimo", "Hey Vimo", "விமோ", "வீமோ", "Bimo".
bool _isWakeKey(String key) {
  if (key.length < 3 || key.length > 6) return false;
  if (!(key.startsWith('v') || key.startsWith('p'))) return false;
  return levenshtein(key, 'vimo') <= 1;
}

/// Index of the wake word ("Vimo") in [tokens], or -1. Also finds it split by
/// the recogniser ("v mo", "we mo").
int findWakeWord(List<String> tokens) {
  for (int i = 0; i < tokens.length; i++) {
    final key = phoneticKey(tokens[i]);
    if (_isWakeKey(key)) return i;
    if (i + 1 < tokens.length && tokens[i].length <= 3) {
      final joined = key + phoneticKey(tokens[i + 1]);
      if (_isWakeKey(joined)) return i + 1;
    }
  }
  return -1;
}

bool _anyWord(List<String> tokens, Set<String> words) =>
    tokens.any(words.contains);

bool _saysFinish(List<String> tokens) {
  if (_anyWord(tokens, _finishWords)) return true;
  final text = tokens.join(' ');
  if (text.contains('that all') ||
      text.contains('thats all') ||
      text.contains('ho gaya') ||
      text.contains('हो गया')) {
    return true;
  }
  for (final t in tokens) {
    final key = phoneticKey(t);
    // முடிஞ்சு, முடிஞ்சது, முடிச்சிட்டேன், முடிந்தது, mudinchu, mudichitten…
    // ("முடியல" = "I can't" stays out: the next sound must be n or s.)
    if (key.length >= 5 &&
        key.startsWith('muti') &&
        (key[4] == 'n' || key[4] == 's' || key[4] == 't')) {
      return true;
    }
    if (key.startsWith('pinis') || key == 'stop' || key == 'stap') return true;
  }
  return false;
}

/// Everything VIMO understood in one spoken sentence.
class VoiceCommand {
  final String text;
  final List<String> tokens;

  /// The sentence contained "Vimo".
  final bool wake;

  /// Words after the wake word (all words when there was none).
  final List<String> rest;
  final List<CowGuess> cows;
  final double? litres;
  final bool yes;
  final bool no;
  final bool cancel;
  final bool finish;

  /// The milk went to a person (sold or given): not a milking entry.
  final bool sale;

  /// "5 இல்லை 9 லிட்டர்": corrects the amount just said or saved.
  final bool correction;

  /// "Morning" or "Evening" when the sentence says which milking.
  final String? session;

  /// The sentence is about yesterday ("நேற்று", "nethu").
  final bool yesterday;

  const VoiceCommand({
    required this.text,
    required this.tokens,
    required this.wake,
    required this.rest,
    required this.cows,
    required this.litres,
    required this.yes,
    required this.no,
    required this.cancel,
    required this.finish,
    this.sale = false,
    this.correction = false,
    this.session,
    this.yesterday = false,
  });

  CowGuess? get cow =>
      cows.isNotEmpty && cows.first.score >= cowMaybeScore ? cows.first : null;

  /// The best cow is clear of every other: no second cow sounds as close.
  bool get cowIsClear {
    final best = cow;
    if (best == null) return false;
    if (cows.length < 2) return true;
    return cows[1].score < cowMaybeScore || best.score - cows[1].score >= .08;
  }

  bool get cowIsSure => cow != null && cow!.score >= cowSureScore && cowIsClear;

  /// Cows that sound alike enough to ask which one was meant.
  List<String> get closeCows {
    final best = cow;
    if (best == null) return const [];
    return cows
        .where((c) => c.score >= cowMaybeScore && best.score - c.score < .08)
        .map((c) => c.name)
        .take(3)
        .toList();
  }

  bool get hasEntryData => cow != null || litres != null;

  /// Nothing useful at all: only filler or noise.
  bool get isEmpty =>
      !hasEntryData && !yes && !no && !cancel && !finish && rest.isEmpty;

  /// How much this reading of the sentence understood, to pick the best of
  /// the recogniser's alternatives.
  double get information =>
      (cow == null ? 0 : 2 + cow!.score) +
      (litres == null ? 0 : 2) +
      (finish ? 1.5 : 0) +
      (yes || no ? 1 : 0) +
      (wake ? .5 : 0);
}

/// Reads one spoken sentence against the ranch's [cows].
VoiceCommand parseVoiceCommand(
  String text,
  List<String> cows, {
  Map<String, List<String>> aliases = const {},
}) {
  final tokens = voiceTokens(text);
  final wakeAt = findWakeWord(tokens);
  final rest = wakeAt < 0 ? tokens : tokens.sublist(wakeAt + 1);
  // Greeting words around the wake word are not commands.
  final words = rest
      .where(
        (t) => !const {
          'hey',
          'hi',
          'hai',
          'ஹே',
          'ஹாய்',
          'ஏய்',
          'ஹேய்',
        }.contains(t),
      )
      .toList();
  final guesses = guessCows(words, cows, aliases: aliases);
  final best = guesses.isNotEmpty && guesses.first.score >= cowMaybeScore
      ? guesses.first
      : null;
  final reading = readLitres(words, skip: best?.tokens ?? const {});
  final litres = reading.value;
  final valid = litres != null && litres > 0 && litres <= 99 ? litres : null;
  final sureCow = best != null && best.score >= cowSureScore;
  // Milk to a person, not from a cow: a sale word ("விற்றேன்", "kuduthen",
  // "bought", "gave … to"), or a name with "-க்கு"/"kitta" that is no cow.
  final milking = _anyWord(words, _milkingWords);
  bool gaveToPerson() {
    for (int i = 0; i < words.length; i++) {
      if (words[i] != 'gave' && words[i] != 'give') continue;
      // "I gave Ravi 2 litres", "gave 5 litres to Mani"; "Lakshmi gave 8
      // litres" is the cow giving milk.
      if (i > 0 && const {'i', 'we', 'naan', 'நான்'}.contains(words[i - 1])) {
        return true;
      }
      if (words.contains('to')) return true;
      final next = i + 1 < words.length ? words[i + 1] : '';
      if (next.isNotEmpty &&
          _numberValue(next) == null &&
          !_commandWords.contains(next) &&
          !sureCow) {
        return true;
      }
    }
    return false;
  }

  final saleWord =
      _anyWord(words, _saleWords) ||
      gaveToPerson() ||
      (words.contains('got') && !sureCow);
  final toPerson =
      !sureCow &&
      !milking &&
      words.any((w) {
        if (_commandWords.contains(w) ||
            _numberValue(w) != null ||
            _cancelWords.contains(w) ||
            _yesWords.contains(w) ||
            _noWords.contains(w)) {
          return false;
        }
        if (w == 'kitta' || w == 'கிட்ட' || w == 'கிட்டே') return true;
        final key = phoneticKey(w);
        return key.length > 3 &&
            (key.endsWith('ku') || key.endsWith('kita')) &&
            !_isUnit(w);
      });
  final sale =
      !milking && (saleWord || toPerson) || (milking && saleWord && !sureCow);
  return VoiceCommand(
    text: text.trim(),
    tokens: tokens,
    wake: wakeAt >= 0,
    rest: words,
    cows: guesses,
    litres: valid,
    yes: _anyWord(words, _yesWords),
    no: _anyWord(words, _noWords),
    cancel: _anyWord(words, _cancelWords),
    finish: _saysFinish(words),
    sale: sale,
    correction: reading.correction,
    session: _anyWord(words, _morningWords)
        ? 'Morning'
        : _anyWord(words, _eveningWords)
        ? 'Evening'
        : null,
    yesterday: _anyWord(words, _yesterdayWords),
  );
}

/// The best reading among the recogniser's alternatives for one sentence.
VoiceCommand bestVoiceCommand(
  List<String> alternatives,
  List<String> cows, {
  Map<String, List<String>> aliases = const {},
}) {
  VoiceCommand? best;
  for (final text in alternatives) {
    if (text.trim().isEmpty) continue;
    final command = parseVoiceCommand(text, cows, aliases: aliases);
    if (best == null || command.information > best.information + .01) {
      best = command;
    }
  }
  return best ?? parseVoiceCommand('', cows);
}
