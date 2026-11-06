/// Ranch work beyond milk: expenses, feed stock, new cows and calves, the
/// doctor, injections, pregnancy, sickness, sales of cows, payments and
/// questions. Pure Dart and deterministic, so every rule is tested on the
/// owner's sample sentences (test/voice_intents_test.dart).
///
/// The tested milk rules in voice_parser.dart stay first; these rules only
/// speak when a sentence carries their own words ("செலவு", "தவுடு",
/// "டாக்டர்", "ஊசி", "சினை", "எவ்வளவு"…).
library;

import 'voice_diagnostics.dart' show VoiceReading;
import 'voice_parser.dart';

// --- words ------------------------------------------------------------------------

bool _has(List<String> tokens, String text, Iterable<String> words) {
  for (final w in words) {
    if (w.contains(' ')) {
      if (text.contains(w)) return true;
    } else if (tokens.contains(w)) {
      return true;
    }
  }
  return false;
}

/// Tokens that start with any of [stems] (Tamil endings vary a lot:
/// செலவு, செலவாச்சு, செலவுக்கு).
bool _starts(List<String> tokens, Iterable<String> stems) {
  for (final t in tokens) {
    for (final s in stems) {
      if (t.startsWith(s)) return true;
    }
  }
  return false;
}

const _expenseStems = [
  'செலவு',
  'செலவ',
  'selavu',
  'selav',
  'spent',
  'spend',
  'expense',
  'bill',
  'கூலி',
  'kooli',
  'cooli',
  'wage',
  'salary',
  'சம்பளம்',
  'sambalam',
  'மருந்து',
  'marundhu',
  'marunthu',
  'medicine',
  'பெட்ரோல்',
  'petrol',
  'டீசல்',
  'diesel',
  'கயிறு',
  'kayiru',
  'rope',
  'கரண்ட்',
  'current',
  'electricity',
  'மின்',
  'water',
  'தண்ணீர்',
  'repair',
  'ரிப்பேர்',
  'transport',
  'வண்டி',
  'auto',
  'bucket',
  'வாளி',
];

const _thavudu = ['தவுடு', 'thavudu', 'thavidu', 'தவிடு', 'bran'];
const _vaikol = ['வைக்கோல்', 'vaikol', 'vaikkol', 'hay', 'straw'];
const _feedOther = ['புண்ணாக்கு', 'punnakku', 'feed', 'தீவனம்', 'theevanam'];

const _useWords = [
  'பயன்படுத்தினேன்',
  'பயன்படுத்தினோம்',
  'போட்டேன்',
  'போட்டோம்',
  'கொடுத்தேன்',
  'கொடுத்தோம்',
  'used',
  'use',
  'gave',
  'fed',
  'kuduthen',
  'koduthen',
  'potten',
  'pottom',
  'payanpaduthinen',
  'kuduthom',
  'vachen',
  'வைத்தேன்',
];
const _buyWords = [
  'received',
  'arrived',
  'vandhathu',
  'came',
  'வாங்கினேன்',
  'வாங்கினோம்',
  'வாங்கிட்டேன்',
  'வாங்கியாச்சு',
  'bought',
  'buy',
  'purchased',
  'purchase',
  'vaanginen',
  'vanginen',
  'vaangunom',
  'vaanginom',
  'vaangiten',
  'vaangitten',
  'vandhuchu',
  'vanthuchu',
  'வந்துச்சு',
  'வந்தது',
];
const _unitWords = {
  'kg': 'kg',
  'kilo': 'kg',
  'kilos': 'kg',
  'கிலோ': 'kg',
  'kgs': 'kg',
  'bag': 'bag',
  'bags': 'bag',
  'மூட்டை': 'bag',
  'moottai': 'bag',
  'mootai': 'bag',
  'sack': 'bag',
  'கட்டு': 'bundle',
  'kattu': 'bundle',
  'bundle': 'bundle',
  'bundles': 'bundle',
};

const _cowWords = [
  'மாடு',
  'maadu',
  'madu',
  'cow',
  'மாட்டை',
  'maaduva',
  'பசு',
  'pasu',
  'cows',
  'cattle',
  'மாடுகள்',
  'maadugal',
];
const _newWords = [
  'புதிய',
  'புது',
  'pudhu',
  'puthu',
  'pudhiya',
  'new',
  'புதுசா',
  'pudhusa',
];
const _addedWords = ['சேர்த்தேன்', 'added', 'add', 'serthen', 'vaangunom'];
const _breeds = {
  'jersey': 'jersey',
  'ஜெர்சி': 'jersey',
  'hf': 'hf',
  'ஹெச்எஃப்': 'hf',
  'holstein': 'hf',
  'sindhi': 'sindhi',
  'சிந்தி': 'sindhi',
  'gir': 'gir',
  'கிர்': 'gir',
  'kangayam': 'kangayam',
  'காங்கேயம்': 'kangayam',
  'naatu': 'native',
  'நாட்டு': 'native',
  'native': 'native',
  'sahiwal': 'sahiwal',
  'சாஹிவால்': 'sahiwal',
  'murrah': 'murrah',
};

const _calfWords = [
  'கன்று',
  'kanru',
  'kandru',
  'kannu',
  'calf',
  'கன்னுக்குட்டி',
  'kannukutti',
  'calves',
  'கன்றுகள்',
  'kanrugal',
];
const _birthWords = [
  'ஈன்றது',
  'ஈன்றாள்',
  'போட்டது',
  'போட்டாள்',
  'பிறந்தது',
  'eenthuchu',
  'eenduchu',
  'eendhuchu',
  'pottuchu',
  'poattuchu',
  'delivered',
  'born',
  'birth',
  'piranthathu',
  'porandhuchu',
  'pirandhuchu',
];
const _female = ['பெண்', 'pen', 'female', 'heifer', 'கிடேரி', 'kidari'];
const _male = ['ஆண்', 'aan', 'male', 'bull', 'காளை', 'kaalai'];

const _doctorWords = [
  'டாக்டர்',
  'doctor',
  'dr',
  'vet',
  'வைத்தியர்',
  'vaithiyar',
  'மருத்துவர்',
  'maruthuvar',
  'veterinary',
  'வைத்தியம்',
  'vaithiyam',
  'treatment',
  'checkup',
  'checked',
];
const _injectionWords = [
  'ஊசி',
  'oosi',
  'injection',
  'vaccine',
  'vaccinated',
  'vaccination',
  'தடுப்பூசி',
  'thaduppoosi',
  'inject',
];
const _vaccines = {
  'fmd': 'fmd',
  'கோமாரி': 'fmd',
  'komari': 'fmd',
  'kaalpunn': 'fmd',
  'hs': 'hs',
  'தொண்டை': 'hs',
  'thondai': 'hs',
  'bq': 'bq',
  'சப்பை': 'bq',
  'brucella': 'brucella',
  'lsd': 'lsd',
  'அம்மை': 'lsd',
  'theileria': 'theileria',
};
const _aiWords = [
  'கருவூட்டல்',
  'karuvootal',
  'karuvoottal',
  'செயற்கை',
  'insemination',
  'inseminated',
  'ai',
  'சினை ஊசி',
  'sinai oosi',
];
const _pregnantWords = [
  'சினை',
  'sinai',
  'sinaiya',
  'சினையாக',
  'pregnant',
  'pregnancy',
  'சினையா',
];
const _confirmWords = [
  'உறுதி',
  'urudhi',
  'uruthi',
  'confirmed',
  'confirm',
  'positive',
  'ஆனது',
  'irukku',
  'இருக்கு',
];
const _symptoms = {
  'காய்ச்சல்': 'fever',
  'kaichal': 'fever',
  'kaaichal': 'fever',
  'fever': 'fever',
  'வயிற்றுப்போக்கு': 'diarrhea',
  'diarrhea': 'diarrhea',
  'diarrhoea': 'diarrhea',
  'loose': 'diarrhea',
  'vayitrupokku': 'diarrhea',
  'kalichal': 'diarrhea',
  'கழிச்சல்': 'diarrhea',
  'நொண்டுகிறது': 'limping',
  'நொண்டு': 'limping',
  'nondukuthu': 'limping',
  'nondu': 'limping',
  'limping': 'limping',
  'lame': 'limping',
  'இருமல்': 'cough',
  'irumal': 'cough',
  'cough': 'cough',
  'coughing': 'cough',
  'thinnala': 'no_appetite',
  'சாப்பிடவில்லை': 'no_appetite',
  'சாப்பிடல': 'no_appetite',
  'appetite': 'no_appetite',
  'eating': 'no_appetite',
  'அசைபோடவில்லை': 'no_rumination',
  'asaipodala': 'no_rumination',
  'rumination': 'no_rumination',
  'ruminating': 'no_rumination',
  'kammi': 'low_milk',
  'குறைஞ்சிடுச்சு': 'low_milk',
  'kuranjiduchu': 'low_milk',
  'குறைவு': 'low_milk',
  'less': 'low_milk',
  'veekkam': 'swelling',
  'வீக்கம்': 'swelling',
  'swelling': 'swelling',
  'bloat': 'bloat',
  'உப்புசம்': 'bloat',
  'uppusam': 'bloat',
};

/// Beginnings of Tamil symptom verbs: இருமுகிறது, வீங்கியிருக்கிறது.
const _symptomStems = {
  'குறைந்': 'low_milk',
  'kuraiyu': 'low_milk',
  'kuranj': 'low_milk',
  'புண்': 'sore',
  'punn': 'sore',
  'wound': 'sore',
  'irumu': 'cough',
  'saapidala': 'no_appetite',
  'saapidala?': 'no_appetite',
  'சரியில்லை': 'sick',
  'sariyillai': 'sick',
  'இருமு': 'cough',
  'வீங்கி': 'swelling',
  'வீக்க': 'swelling',
  'நொண்டு': 'limping',
  'காய்ச்ச': 'fever',
  'ஜுர': 'fever',
  'jwar': 'fever',
  'swoll': 'swelling',
  'vomit': 'vomiting',
  'வாந்தி': 'vomiting',
};

const _diseases = {
  'nondi': 'lameness',
  'komaari': 'fmd',
  'uppusam': 'bloat',
  'kaal nondi': 'lameness',
  'கால் நொண்டி': 'lameness',
  'மடி வீக்கம்': 'mastitis',
  'madi veekkam': 'mastitis',
  'வயிற்று உப்புசம்': 'bloat',
  'vayitru uppusam': 'bloat',
  'மடிவீக்கம்': 'mastitis',
  'மடிவீக்க': 'mastitis',
  'madi': 'mastitis',
  'mastitis': 'mastitis',
  'கோமாரி': 'fmd',
  'komari': 'fmd',
  'fmd': 'fmd',
  'bloat': 'bloat',
  'உப்புசம்': 'bloat',
  'lameness': 'lameness',
  'நொண்டி': 'lameness',
  'தொண்டை': 'hs',
  'hs': 'hs',
  'அம்மை': 'lsd',
  'lsd': 'lsd',
  'milk fever': 'milk_fever',
};
const _saidWords = [
  'உறுதி செய்தார்கள்',
  'உறுதி செய்தார்',
  'urudhi pannaanga',
  'urudhi pannar',
  'sonnaaru',
  'சொன்னாரு',
  'சொன்னார்',
  'சொன்னாங்க',
  'said',
  'says',
  'diagnosed',
  'urudhi pannaanga',
  'sonnaar',
  'sonnanga',
  'சொல்லிட்டார்',
  'என்று சொன்னார்',
  'nu sonnaar',
];
const _soldWords = [
  'vithaachu',
  'vittachu',
  'விற்றாச்சு',
  'வித்தாச்சு',
  'விற்றேன்',
  'வித்தேன்',
  'விற்றோம்',
  'sold',
  'vitten',
  'vithen',
  'vittom',
  'vithom',
  'விற்பனை',
  'vittaen',
];
const _paidWords = [
  'கொடுத்தார்',
  'கொடுத்தாங்க',
  'குடுத்தாரு',
  'kuduthaaru',
  'koduthaaru',
  'kuduthar',
  'paid',
  'pay',
  'pannaaru',
  'pannanga',
  'செலுத்தினார்',
  'kuduthanga',
];
const _questionWords = [
  'எவ்வளவு',
  'எத்தனை',
  'ethana',
  'ethanai',
  'evvalavu',
  'evlo',
  'evvlo',
  'how',
  'what',
  'sollu',
  'சொல்லு',
  'சொல்',
  'எவ்ளோ',
  'enna',
  'என்ன',
  'left',
  'which',
  'edhu',
  'எந்த',
  'யார்',
  'yaar',
  'sales',
  'count',
  'number',
  'entha',
  'endha',
  'check',
  'ranking',
  'தரவரிசை',
  'most',
  'adhiga',
  'அதிக',
];

/// Small talk VIMO does not record: "hello", "thanks", the weather.
const _chatWords = [
  'hello',
  'hi',
  'thanks',
  'thank',
  'weather',
  'மழை',
  'mazhai',
  'paattu',
  'song',
  'paadu',
  'joke',
  'who',
  'யார் நீ',
  'vanakkam',
  'வணக்கம்',
  'news',
];

/// Plans for later ("நாளை ஊசி போட வேண்டும்", "remind me"): not recorded.
const _futureWords = [
  'நாளை',
  'naalai',
  'naalaiku',
  'tomorrow',
  'remind',
  'next',
  'அடுத்த',
  'adutha',
  'வேண்டும்',
  'vendum',
  'kaattanum',
  'podanum',
  'poda',
  'போட',
  'eppo',
  'எப்போது',
  'when',
  'due',
  'vilai',
  'விலை',
  'price',
  'rate',
];
const _showWords = [
  'காட்டு',
  'kaattu',
  'kattu',
  'show',
  'history',
  'வரலாறு',
  'varalaaru',
  'pathivugal',
  'பதிவுகள்',
  'records',
  'list',
];
const _todayWords = [
  'இன்று',
  'இன்னைக்கு',
  'இன்னிக்கு',
  'innaiku',
  'inniki',
  'innikku',
  'indru',
  'today',
];
const _yesterdayWords = [
  'நேற்று',
  'நேத்து',
  'netru',
  'nethu',
  'neththu',
  'yesterday',
];
const _weekWords = ['வாரம்', 'vaaram', 'week'];
const _monthWords = ['மாதம்', 'மாத', 'maasam', 'masam', 'month', 'மாசம்'];
const _yearWords = ['வருடம்', 'வருஷம்', 'varusham', 'year'];
const _allWords = [
  'இதுவரை',
  'ithuvarai',
  'ithu varai',
  'so far',
  'all',
  'ever',
];
// Not "பாலு"/"paalu": that is also the name Balu.
const _milkWords = ['பால்', 'paal', 'milk'];

// --- numbers and money ----------------------------------------------------------

const _tensTa = {
  'இருபது': 20,
  'முப்பது': 30,
  'நாற்பது': 40,
  'ஐம்பது': 50,
  'அம்பது': 50,
  'அறுபது': 60,
  'எழுபது': 70,
  'எண்பது': 80,
  'தொண்ணூறு': 90,
  'நூறு': 100,
  'இருநூறு': 200,
  'முன்னூறு': 300,
  'நானூறு': 400,
  'ஐநூறு': 500,
  'அறுநூறு': 600,
  'எழுநூறு': 700,
  'எண்ணூறு': 800,
  'தொள்ளாயிரம்': 900,
  'ஆயிரம்': 1000,
};
const _tensLatin = {
  'irubathu': 20,
  'iruvathu': 20,
  'mupathu': 30,
  'muppathu': 30,
  'naarpathu': 40,
  'narpathu': 40,
  'aimbathu': 50,
  'ambathu': 50,
  'arubathu': 60,
  'ezhubathu': 70,
  'enbathu': 80,
  'thonnooru': 90,
  'nooru': 100,
  'hundred': 100,
  'irunooru': 200,
  'munnooru': 300,
  'naanooru': 400,
  'ainooru': 500,
  'aayiram': 1000,
  'thousand': 1000,
};

/// The amounts in [tokens], biggest first: digits ("20000", "2,500"),
/// "5 ஆயிரம்", "ஐநூறு", "two thousand", "1.5 lakh".
List<double> amountsIn(List<String> tokens) {
  final values = <double>[];
  for (int i = 0; i < tokens.length; i++) {
    final t = tokens[i].replaceAll(',', '');
    final next = i + 1 < tokens.length ? tokens[i + 1] : '';
    final multiplier = const {
      'ஆயிரம்',
      'aayiram',
      'thousand',
      'ஆயிரத்து',
      'லட்சம்',
      'lakh',
      'latcham',
      'lakhs',
      'hundred',
      'நூறு',
      'nooru',
    }.contains(next);
    var v =
        double.tryParse(t) ??
        (_tensTa[t] ?? _tensLatin[t])?.toDouble() ??
        // "rendu aayiram": a small number word before thousand/hundred.
        (multiplier ? extractLitres([t]) : null);
    if (v == null) continue;
    if (const {'ஆயிரம்', 'aayiram', 'thousand', 'ஆயிரத்து'}.contains(next)) {
      v *= 1000;
      i++;
    } else if (const {'லட்சம்', 'lakh', 'latcham', 'lakhs'}.contains(next)) {
      v *= 100000;
      i++;
    } else if (const {'hundred', 'நூறு', 'nooru'}.contains(next) && v < 10) {
      v *= 100;
      i++;
    }
    values.add(v);
  }
  return values;
}

const _moneyWords = {
  'rs',
  'rs.',
  'rupees',
  'rupee',
  'rupaai',
  'rupai',
  'ruba',
  'ரூபாய்',
  'ரூபாய்க்கு',
  'ரூ',
  'rupaaiku',
  'rupaiku',
  '₹',
  'inr',
};

double? _moneyAmount(List<String> tokens) {
  // Prefer a number next to a money word, else the biggest number.
  for (int i = 0; i < tokens.length; i++) {
    if (!_moneyWords.contains(tokens[i])) continue;
    for (final j in [i - 1, i + 1]) {
      if (j < 0 || j >= tokens.length) continue;
      final a = amountsIn(tokens.sublist(j, (j + 2).clamp(0, tokens.length)));
      if (a.isNotEmpty) return a.first;
    }
  }
  final all = amountsIn(tokens);
  if (all.isEmpty) return null;
  all.sort();
  return all.last;
}

double? _quantity(List<String> tokens) {
  for (int i = 0; i < tokens.length; i++) {
    if (_unitWords.containsKey(tokens[i]) && i > 0) {
      final v =
          extractLitres([tokens[i - 1]]) ??
          (i > 1 ? extractLitres(tokens.sublist(i - 2, i)) : null);
      if (v != null) return v;
    }
  }
  return extractLitres(tokens);
}

String? _unit(List<String> tokens) {
  for (final t in tokens) {
    final u = _unitWords[t];
    if (u != null) return u;
  }
  return null;
}

String? _item(List<String> tokens, String text) {
  if (_has(tokens, text, _thavudu)) return 'thavudu';
  if (_has(tokens, text, _vaikol)) return 'vaikol';
  return null;
}

String _date(List<String> tokens, String text) =>
    _has(tokens, text, _yesterdayWords) ? 'yesterday' : 'today';

String? _range(List<String> tokens, String text) {
  if (_has(tokens, text, _allWords)) return 'all';
  if (_has(tokens, text, _yesterdayWords)) return 'yesterday';
  if (_has(tokens, text, _weekWords)) return 'this_week';
  if (_starts(tokens, _monthWords)) return 'this_month';
  if (_has(tokens, text, _yearWords)) return 'this_year';
  if (_has(tokens, text, _todayWords)) return 'today';
  return null;
}

// --- names ----------------------------------------------------------------------

const _notNames = {
  'vimo',
  'விமோ',
  'sir',
  'ஐயா',
  'ok',
  'okay',
  'சரி',
  'சரியா',
  'today',
  'இன்று',
  'yesterday',
  'நேற்று',
  'please',
  'the',
  'a',
  'to',
  'for',
  'of',
  'i',
  'we',
  'my',
  'gave',
  'paid',
  'bought',
  'sold',
  'milk',
  'பால்',
  'paal',
  'cow',
  'மாடு',
  'maadu',
  'new',
  'புதிய',
  'pudhu',
  'calf',
  'கன்று',
  'doctor',
  'டாக்டர்',
  'litre',
  'litres',
  'liter',
  'liters',
  'லிட்டர்',
  'innaiku',
  'inniki',
  'indru',
  'netru',
  'nethu',
  'neththu',
  'innikku',
  'காலை',
  'மாலை',
  'morning',
  'evening',
  'kaalai',
  'maalai',
  'anna',
  'akka',
  'ayya',
  'aiya',
  'அண்ணா',
  'அக்கா',
  'has',
  'is',
  'was',
  'and',
  'or',
  'from',
  'with',
  'how',
  'much',
  'many',
  'what',
  'did',
  'take',
  'took',
  'get',
  'got',
  'enga',
  'veetuku',
  'யார்',
  'yaar',
  'ellam',
  'எல்லாம்',
  'nu',
  'என்று',
  'named',
  'called',
};

/// Strips Tamil/Hindi case endings from a name: "சரவணனுக்கு" → "சரவணன்",
/// "karthikku" → "karthik", "kaveriku" → "kaveri".
String stripNameEnding(String word) {
  const tamil = [
    'வுக்கு',
    'னுக்கு',
    'ுக்கு',
    'க்கு',
    'கிட்ட',
    'இடம்',
    'வை',
    'ஐ',
    'யை',
    'வின்',
    'ின்',
    'க்',
    'யிடம்',
    'விடம்',
  ];
  for (final e in tamil) {
    if (word.length > e.length + 1 && word.endsWith(e)) {
      var stem = word.substring(0, word.length - e.length);
      if (e == 'னுக்கு') stem = '$stemன்';
      if (e == 'ுக்கு' && !stem.endsWith('்')) stem = '$stem்';
      return stem;
    }
  }
  const latin = ['vukku', 'ukku', 'kku', 'ku', 'kitta', 'ki', 'ko', 'ke', 'va'];
  for (final e in latin) {
    if (word.length > e.length + 2 && word.endsWith(e)) {
      return word.substring(0, word.length - e.length);
    }
  }
  return word;
}

bool _nameLike(String t) =>
    t.length > 1 &&
    !_notNames.contains(t) &&
    double.tryParse(t) == null &&
    !_moneyWords.contains(t) &&
    !_unitWords.containsKey(t) &&
    extractLitres([t]) == null;

/// The cow a sentence names, by sound among [cows], else a name-like word
/// next to "மாடு"/"cow".
String? cowIn(
  List<String> tokens,
  List<String> cows,
  Map<String, List<String>> aliases,
) {
  final guesses = guessCows(tokens, cows, aliases: aliases);
  if (guesses.isNotEmpty && guesses.first.score >= cowSureScore) {
    return guesses.first.name;
  }
  for (int i = 0; i < tokens.length; i++) {
    if (!_cowWords.contains(tokens[i])) continue;
    if (i > 0 && _nameLike(tokens[i - 1])) {
      return stripNameEnding(tokens[i - 1]);
    }
    if (i + 1 < tokens.length && _nameLike(tokens[i + 1])) {
      return stripNameEnding(tokens[i + 1]);
    }
  }
  return null;
}

/// The person a sale or payment names: "சரவணனுக்கு", "Ravi bought",
/// "to Karthik", "selvi akka ku".
String? personIn(List<String> tokens, {Set<String> skip = const {}}) {
  bool ok(String t) => _nameLike(t) && !skip.contains(t);
  for (int i = 0; i < tokens.length; i++) {
    final t = tokens[i];
    if ((t == 'to' || t == 'gave') &&
        i + 1 < tokens.length &&
        ok(tokens[i + 1])) {
      return tokens[i + 1];
    }
  }
  for (final t in tokens) {
    final stem = stripNameEnding(t);
    if (stem != t && ok(stem) && ok(t)) return stem;
  }
  for (int i = 0; i < tokens.length; i++) {
    final t = tokens[i];
    if (!ok(t)) continue;
    final next = i + 1 < tokens.length ? tokens[i + 1] : '';
    if (const {
      'ku',
      'kku',
      'kitta',
      'anna',
      'akka',
      'ayya',
      'அண்ணா',
      'அக்கா',
      'கிட்ட',
    }.contains(next)) {
      return t;
    }
  }
  // "Ravi bought milk", "Kannan 200 ரூபாய் கொடுத்தார்": the first name-like word.
  for (final t in tokens) {
    if (ok(t) && !_isKeyword(t)) return stripNameEnding(t);
  }
  return null;
}

bool _isKeyword(String t) {
  for (final list in [
    _expenseStems,
    _useWords,
    _buyWords,
    _soldWords,
    _paidWords,
    _milkWords,
    _questionWords,
    _showWords,
    _doctorWords,
    _injectionWords,
    _calfWords,
    _birthWords,
    _pregnantWords,
    _confirmWords,
    _aiWords,
    _saidWords,
    _newWords,
    _addedWords,
    _thavudu,
    _vaikol,
    _feedOther,
  ]) {
    for (final w in list) {
      if (t == w || (w.length > 3 && t.startsWith(w))) return true;
    }
  }
  return _symptoms.containsKey(t) ||
      _diseases.containsKey(t) ||
      _breeds.containsKey(t) ||
      _vaccines.containsKey(t) ||
      const [
        'vaangunaaru',
        'vaanginaar',
        'vaanginar',
        'வாங்கினார்',
        'koduthaen',
        'kuduthen',
        'கொடுத்தேன்',
        'விற்றேன்',
        'pathivugal',
        'irukku',
        'ullathu',
      ].contains(t);
}

/// "Luna nu pudhu maadu", "புதிய மாடு மாதவி", "new Jersey cow Karuppi".
String? _newCowName(List<String> tokens) {
  for (int i = 0; i < tokens.length; i++) {
    if ((tokens[i] == 'nu' || tokens[i] == 'என்று' || tokens[i] == 'named') &&
        i > 0 &&
        _nameLike(tokens[i - 1])) {
      return tokens[i - 1];
    }
  }
  for (int i = 0; i < tokens.length; i++) {
    if (!_cowWords.contains(tokens[i])) continue;
    for (final j in [i + 1, i - 1]) {
      if (j < 0 || j >= tokens.length) continue;
      final t = tokens[j];
      if (_nameLike(t) &&
          !_isKeyword(t) &&
          !_newWords.contains(t) &&
          !_breeds.containsKey(t)) {
        return stripNameEnding(t);
      }
    }
  }
  for (final t in tokens) {
    if (_nameLike(t) && !_isKeyword(t) && !_breeds.containsKey(t)) {
      return stripNameEnding(t);
    }
  }
  return null;
}

/// "7 varusham 6 maasam" → 90, "one and a half years" → 18, "8 மாதம்" → 8.
int? ageMonthsIn(List<String> tokens) {
  double months = 0;
  var found = false;
  for (int i = 0; i < tokens.length; i++) {
    final t = tokens[i];
    final isYear =
        _yearWords.any(t.startsWith) || t == 'years' || t == 'vayasu';
    final isMonth = _monthWords.any(t.startsWith) || t == 'months';
    if (!isYear && !isMonth) continue;
    double? n;
    for (var back = 1; back <= 4 && i - back >= 0; back++) {
      n = extractLitres(tokens.sublist(i - back, i));
      if (n != null) break;
    }
    if (n == null) continue;
    months += isYear ? n * 12 : n;
    found = true;
  }
  return found ? months.round() : null;
}

// --- intents ----------------------------------------------------------------------

/// The extra intent of [text], or null when it carries none of these words.
VoiceReading? extraIntent(
  String text, {
  List<String> cows = const [],
  Map<String, List<String>> aliases = const {},
}) {
  final tokens = voiceTokens(
    text,
  ).where((t) => !const {'vimo', 'விமோ', 'hey', 'ஹே'}.contains(t)).toList();
  if (tokens.isEmpty) return null;
  final s = tokens.join(' ');
  final date = _date(tokens, s);
  String? cow() => cowIn(tokens, cows, aliases);

  final money = _moneyAmount(tokens);
  final hasMoneyWord = tokens.any(_moneyWords.contains);
  final milkWord = _has(tokens, s, _milkWords);
  final cowWord = _has(tokens, s, _cowWords);
  final item = _item(tokens, s);

  // Money owed to the ranch: "கண்ணன் இடம் எவ்வளவு வர வேண்டும்".
  if (s.contains('வர வேண்டும்') ||
      s.contains('varanum') ||
      _starts(tokens, [
        'baaki',
        'பாக்கி',
        'dues',
        'owe',
        'tharanum',
        'balance',
      ])) {
    return (
      intent: 'query',
      slots: {'metric': 'dues', 'name': personIn(tokens)},
    );
  }
  if (_has(tokens, s, _chatWords) &&
      money == null &&
      extractLitres(tokens) == null &&
      cow() == null) {
    return (intent: 'unknown', slots: const {});
  }
  if (s.contains('enna aachu') ||
      s.contains('என்ன ஆச்சு') ||
      tokens.contains('theriyala')) {
    return (
      intent: 'symptom',
      slots: {
        'cow': cow(),
        'symptoms': ['unknown_illness'],
        'date': date,
      },
    );
  }
  // Sickness: "சிவப்பி மாடு காய்ச்சல்", "udambu sari illa".
  final symptoms = <String>{
    for (final t in tokens)
      if (_symptoms[t] != null) _symptoms[t]!,
    for (final t in tokens)
      for (final e in _symptomStems.entries)
        if (t.startsWith(e.key)) e.value,
    if (s.contains('paal kammi') || s.contains('பால் குறை')) 'low_milk',
    if (s.contains('not eating') || s.contains('தீவனம் சாப்பிட')) 'no_appetite',
    if (s.contains('udambu sari') ||
        s.contains('உடம்பு சரி') ||
        s.contains('is sick') ||
        tokens.contains('sick'))
      'sick',
    if (s.contains('kannula neer') ||
        s.contains('கண்ணில் நீர்') ||
        s.contains('kann la neer'))
      'eye_discharge',
    if (s.contains('vayiru pog') || s.contains('வயிறு போ')) 'diarrhea',
    if (s.contains('asai poda') || s.contains('அசை போட')) 'no_rumination',
    if (s.contains('not well') || s.contains('sariya illa')) 'sick',
    if (s.contains('enna aachu') || s.contains('என்ன ஆச்சு')) 'unknown_illness',
  };
  if (symptoms.isNotEmpty && money == null) {
    // "மடி வீக்கம் என்று உறுதி செய்தார்கள்": the doctor's word wins.
    final disease = _diagnosed(tokens, s);
    if (disease != null) {
      return (
        intent: 'diagnosis',
        slots: {'cow': cow(), 'disease': disease, 'date': date},
      );
    }
    return (
      intent: 'symptom',
      slots: {'cow': cow(), 'symptoms': symptoms.toList(), 'date': date},
    );
  }

  // Plans and reminders are not records.
  if (_has(tokens, s, _futureWords) && !_has(tokens, s, _showWords)) {
    return (intent: 'unknown', slots: const {});
  }
  // Records to show: "இந்த மாதம் பால் வரலாறு காட்டு".
  if (_has(tokens, s, _showWords) &&
      (milkWord ||
          _starts(tokens, [
            'pathiv',
            'பதிவு',
            'record',
            'history',
            'வரலாறு',
          ]))) {
    if (_has(tokens, s, ['ranking', 'தரவரிசை'])) {
      return (
        intent: 'query',
        slots: {'metric': 'ranking', 'range': _range(tokens, s) ?? 'today'},
      );
    }
    return (
      intent: 'history',
      slots: {'metric': 'milk', 'range': _range(tokens, s) ?? 'today'},
    );
  }
  if (_has(tokens, s, _showWords) && _has(tokens, s, _pregnantWords)) {
    return (intent: 'query', slots: {'metric': 'pregnant_count'});
  }
  if (_starts(tokens, ['profit', 'லாபம்', 'laabam', 'labam', 'laabham'])) {
    return (
      intent: 'query',
      slots: {'metric': 'profit', 'range': _range(tokens, s) ?? 'this_month'},
    );
  }

  final plain =
      !_has(tokens, s, _paidWords) &&
      money == null &&
      extractLitres(tokens) == null &&
      !tokens.contains('received');
  final weakAsk =
      _has(tokens, s, ['sollu', 'சொல்லு', 'சொல்', 'please']) ||
      text.trim().endsWith('?');
  final totalAsk =
      _has(tokens, s, ['total', 'motham', 'மொத்தம்', 'mottham']) &&
      extractLitres(tokens) == null;
  // "Gowri milk yesterday": a milk word, a day, no amount and no verb.
  final bareMilk =
      milkWord &&
      extractLitres(tokens) == null &&
      !tokens.contains('from') &&
      _range(tokens, s) != null &&
      !_starts(tokens, [
        'kudu',
        'kodu',
        'கொடு',
        'குடு',
        'gave',
        'karan',
        'கறந்',
        'milked',
        'கிடை',
        'kedai',
        'vaang',
        'வாங்க',
        'sold',
        'vit',
        'விற்',
      ]);
  final asking =
      (_has(tokens, s, _questionWords) && (plain || money == null)) ||
      (weakAsk && plain) ||
      totalAsk ||
      bareMilk;
  if (asking) {
    final range = _range(tokens, s);
    if (item != null) {
      return (intent: 'query', slots: {'metric': 'stock', 'item': item});
    }
    if (_has(tokens, s, ['ranking', 'தரவரிசை', 'most', 'adhiga', 'அதிக'])) {
      return (
        intent: 'query',
        slots: {'metric': 'ranking', 'range': range ?? 'today'},
      );
    }
    if (_has(tokens, s, _calfWords)) {
      return (intent: 'query', slots: {'metric': 'calf_count'});
    }
    if (_has(tokens, s, _pregnantWords)) {
      return (intent: 'query', slots: {'metric': 'pregnant_count'});
    }
    if (_starts(tokens, _expenseStems)) {
      return (
        intent: 'query',
        slots: {'metric': 'expense', 'range': range ?? 'this_month'},
      );
    }
    final sold = _starts(tokens, [
      'vitta',
      'விற்ற',
      'sold',
      'sales',
      'sale',
      'vaanginaar',
      'வாங்கினார்',
      'vaangunaaru',
      'vaangi',
      'வாங்கின',
      'bought',
      'took',
    ]);
    if (milkWord || sold || range != null) {
      if (sold) {
        return (
          intent: 'query',
          slots: {
            'metric': 'milk_sold',
            'range': range ?? 'today',
            'name': personIn(tokens),
          },
        );
      }
      return (
        intent: 'query',
        slots: {'metric': 'milk', 'range': range ?? 'today', 'cow': cow()},
      );
    }
    if (cowWord) return (intent: 'query', slots: {'metric': 'cow_count'});
  }

  // A new calf: "கௌரி பெண் கன்று ஈன்றது", "Rani gave birth to a calf".
  if ((_has(tokens, s, _calfWords) && _starts(tokens, _birthWords)) ||
      s.contains('gave birth')) {
    final gender = _has(tokens, s, _female)
        ? 'female'
        : _has(tokens, s, _male)
        ? 'male'
        : null;
    return (
      intent: 'calf_birth',
      slots: {'cow': cow(), 'gender': gender, 'date': date},
    );
  }

  // Pregnancy and insemination.
  if (_has(tokens, s, _pregnantWords) &&
      _starts(tokens, _confirmWords) &&
      !_has(tokens, s, _injectionWords)) {
    return (intent: 'pregnancy_confirmed', slots: {'cow': cow(), 'date': date});
  }
  if (_has(tokens, s, _aiWords) || RegExp(r'(^| )ai pot').hasMatch(s)) {
    return (intent: 'insemination', slots: {'cow': cow(), 'date': date});
  }

  // The doctor's diagnosis: "கோமாரி என்று உறுதி செய்தார்கள்".
  String? disease;
  for (final e in _diseases.entries) {
    if (disease != null) break;
    if (e.key.contains(' ')) {
      if (s.contains(e.key)) disease = e.value;
    } else if (tokens.contains(e.key) ||
        (e.key.length > 3 && tokens.any((t) => t.startsWith(e.key)))) {
      disease = e.value;
    }
  }
  final said =
      _has(tokens, s, _saidWords) || _starts(tokens, ['urudhi', 'உறுதி']);
  if (disease != null && said) {
    return (
      intent: 'diagnosis',
      slots: {'cow': cow(), 'disease': disease, 'date': date},
    );
  }

  // Doctor's fee booked as an expense: "மாட்டு மருத்துவர் கட்டணம் 500".
  if (s.contains('மருத்துவர் கட்டணம்') && money != null) {
    return (
      intent: 'expense',
      slots: {'name': _expenseName(tokens), 'amount': money, 'date': date},
    );
  }
  if (_has(tokens, s, _doctorWords)) {
    return (
      intent: 'vet_visit',
      slots: {'cow': cow(), 'fee': money, 'date': date},
    );
  }
  if (_has(tokens, s, _injectionWords) ||
      _starts(tokens, ['vaccin', 'தடுப்பூசி'])) {
    String? vaccine;
    for (final t in tokens) {
      vaccine ??= _vaccines[t];
    }
    return (
      intent: 'vaccination',
      slots: {'cow': cow(), 'vaccine': vaccine, 'date': date},
    );
  }

  // A cow sold: "rani maaduva 40000 rupaaiku vitten".
  final soldWord = _has(tokens, s, _soldWords);
  if (soldWord &&
      !milkWord &&
      (cowWord || (money ?? 0) >= 1000 || cow() != null)) {
    return (
      intent: 'sell_cow',
      slots: {'cow': cow(), 'amount': money, 'date': date},
    );
  }

  // A cow bought or added: "Luna nu pudhu maadu vaangunom".
  final buying =
      _has(tokens, s, _buyWords) || _starts(tokens, ['vaang', 'வாங்கி']);
  final newCow =
      (_has(tokens, s, _newWords) && (cowWord || buying)) ||
      (cowWord && buying && !milkWord) ||
      (tokens.contains('purchased') && money != null) ||
      (tokens.contains('added') && cowWord);
  if (newCow && item == null) {
    String? breed;
    for (final t in tokens) {
      breed ??= _breeds[t];
    }
    final added = _has(tokens, s, ['சேர்த்தேன்', 'added', 'serthen']);
    return (
      intent: 'add_cow',
      slots: {
        'name': _newCowName(tokens),
        'breed': breed,
        'age_months': ageMonthsIn(tokens),
        'amount': money,
        'source': added ? 'added' : 'bought',
        'date': date,
      },
    );
  }
  // Money received: "murugan 500 rupaai kuduthaaru", "received 800 from
  // Selvi", "ரவி கிட்ட 300 ரூபாய் வாங்கினேன்".
  final received =
      _has(tokens, s, _paidWords) ||
      tokens.contains('received') ||
      (tokens.any((t) => t == 'kitta' || t == 'கிட்ட') &&
          (_has(tokens, s, _buyWords) ||
              _starts(tokens, ['vaang', 'வாங்க']))) ||
      (tokens.contains('gave') && hasMoneyWord && !milkWord && item == null);
  if (received &&
      money != null &&
      !milkWord &&
      item == null &&
      !_starts(tokens, _expenseStems)) {
    return (
      intent: 'payment',
      slots: {'name': personIn(tokens), 'amount': money, 'date': date},
    );
  }

  // Expenses: "கயிறு 150 ரூபாய்", "வைக்கோல் கூலி 300", "petrol 300".
  final expenseWord = _starts(tokens, _expenseStems);
  // "petrol selavu", "spent on rope": a named cost even without an amount.
  final namedCost = tokens.any(
    (t) => _expenseStems.any(
      (stem) =>
          t.startsWith(stem) &&
          !const {
            'செலவு',
            'செலவ',
            'selavu',
            'selav',
            'spent',
            'spend',
            'expense',
          }.contains(stem),
    ),
  );
  if ((money != null &&
          (expenseWord ||
              (hasMoneyWord && !milkWord && !cowWord && item == null))) ||
      (expenseWord && namedCost && item == null)) {
    return (
      intent: 'expense',
      slots: {'name': _expenseName(tokens), 'amount': money, 'date': date},
    );
  }

  // Feed stock: bought (in) or used.
  if (item != null) {
    final bought =
        _has(tokens, s, _buyWords) || _starts(tokens, ['vaang', 'வாங்க']);
    return (
      intent: bought ? 'stock_in' : 'stock_use',
      slots: {
        'item': item,
        'qty': _quantity(tokens),
        'unit': _unit(tokens),
        'date': date,
      },
    );
  }

  return null;
}

/// The disease a sentence says the doctor confirmed, or null.
String? _diagnosed(List<String> tokens, String s) {
  final said =
      _has(tokens, s, _saidWords) || _starts(tokens, ['urudhi', 'உறுதி']);
  if (!said) return null;
  for (final e in _diseases.entries) {
    if (e.key.contains(' ')) {
      if (s.contains(e.key)) return e.value;
    } else if (tokens.contains(e.key) ||
        (e.key.length > 3 && tokens.any((t) => t.startsWith(e.key)))) {
      return e.value;
    }
  }
  return null;
}

String? _expenseName(List<String> tokens) {
  final words = [
    for (final t in tokens)
      if (!_moneyWords.contains(t) &&
          double.tryParse(t.replaceAll(',', '')) == null &&
          !_tensTa.containsKey(t) &&
          !_tensLatin.containsKey(t) &&
          !const {
            'செலவு',
            'selavu',
            'spent',
            'expense',
            'on',
            'for',
            'paid',
            'கொடுத்தேன்',
            'kuduthen',
            'today',
            'இன்று',
            'yesterday',
            'நேற்று',
            'sir',
            'ஐயா',
            'சரியா',
            'சரி',
            'ok',
            'please',
            'ஆச்சு',
            'aachu',
            'ஆனது',
            'rupees',
            'innaiku',
            'inniki',
            'netru',
            'nethu',
            'this',
            'week',
            'i',
            'ஆயிரம்',
            'aayiram',
            'thousand',
            'pannen',
            'panninen',
            'வாங்கினேன்',
            'koduthen',
            'koduthaen',
            'கொடுத்தோம்',
            'potten',
            'செலவாச்சு',
            'aagiduchu',
          }.contains(t))
        t,
  ];
  if (words.isEmpty) return null;
  return words.take(4).join(' ');
}
