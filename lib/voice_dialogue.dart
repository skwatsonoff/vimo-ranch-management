/// Follow-up questions for voice entries other than milk: a small,
/// deterministic slot-filling machine. Every sentence VIMO speaks comes
/// from a fixed template (Tamil, Tanglish, English), never written freely,
/// so the Tamil is always correct.
///
/// "Luna nu pudhu maadu vaangunom" → "லூனாவுக்கு புதிய profile
/// உருவாக்கவா?" → "ஆமா" → "இப்போது புகைப்படம் எடுக்கவா?" → "இல்ல" →
/// "லூனாவுக்கு எத்தனை மாத வயசு?" → "ரெண்டு வருஷம்" → "என்ன இனம்?" →
/// "ஜெர்சி" → the cow is created.
library;

import 'voice_diagnostics.dart' show VoiceReading;
import 'voice_intents_extra.dart';
import 'voice_parser.dart';

/// One sentence VIMO says.
class VoiceLine {
  final String ta, tanglish, en;
  const VoiceLine(this.ta, this.tanglish, this.en);
}

/// What the screen should do once a flow is complete.
class VoiceAction {
  final String kind;
  final Map<String, Object?> data;
  const VoiceAction(this.kind, this.data);
}

class DialogueTurn {
  final VoiceLine? say;
  final VoiceAction? action;

  /// The flow is over (done or dropped).
  final bool finished;
  const DialogueTurn({this.say, this.action, this.finished = false});
}

/// Intents this dialogue handles (milk entries stay in the milk flow).
const dialogueIntents = {
  'add_cow',
  'expense',
  'stock_use',
  'stock_in',
  'vet_visit',
  'vaccination',
  'insemination',
  'pregnancy_confirmed',
  'symptom',
  'diagnosis',
  'calf_birth',
  'sell_cow',
  'payment',
  'query',
  'history',
};

/// Intents VIMO notes but leaves for the app's own screens to complete.
const _notSavedByVoice = {'sell_cow', 'payment'};

const _breedNames = {
  'jersey': ('Jersey Cross', 'ஜெர்சி'),
  'hf': ('HF Cross', 'HF'),
  'gir': ('Gir', 'கிர்'),
  'sahiwal': ('Sahiwal', 'சாஹிவால்'),
  'sindhi': ('Red Sindhi', 'சிந்தி'),
  'kangayam': ('Kangeyam', 'காங்கேயம்'),
  'native': ('Native Cow', 'நாட்டு மாடு'),
};

const _unknownWords = {
  'தெரியாது',
  'theriyadhu',
  'theriyathu',
  'theriyala',
  'தெரியல',
  'unknown',
  "don't",
  'dont',
  'skip',
  'விடு',
  'vidu',
  'pass',
  'illa',
  'இல்லை',
};

bool _saysUnknown(List<String> tokens) => tokens.any(_unknownWords.contains);

class VoiceDialogue {
  VoiceDialogue({required this.cows, String Function(String name)? tamilName})
    : tamilName = tamilName ?? ((n) => n);

  /// The ranch's cows, to understand "which cow" answers.
  final List<String> Function() cows;

  /// A name in Tamil letters for Tamil sentences.
  final String Function(String name) tamilName;

  String? _intent;
  Map<String, Object?> _slots = {};
  String? _asking;
  bool _confirmed = false;
  final List<String> _heard = [];

  bool get active => _intent != null;
  String? get intent => _intent;
  String? get asking => _asking;
  Map<String, Object?> get slots => Map.unmodifiable(_slots);

  void reset() {
    _intent = null;
    _slots = {};
    _asking = null;
    _confirmed = false;
    _heard.clear();
  }

  /// Starts a flow for [reading] (heard as [text]).
  DialogueTurn start(VoiceReading reading, String text) {
    reset();
    _intent = reading.intent;
    _slots = Map.of(reading.slots);
    _heard.add(text);
    if (reading.intent == 'query' || reading.intent == 'history') {
      final action = VoiceAction(reading.intent, Map.of(_slots));
      reset();
      return DialogueTurn(action: action, finished: true);
    }
    if (_notSavedByVoice.contains(reading.intent)) {
      reset();
      return const DialogueTurn(
        say: VoiceLine(
          'இதை Sell / கணக்கு பக்கத்தில் பதிவு செய்யுங்கள். குரல் இதை இன்னும் சேமிக்காது.',
          'Idhai Sell pakkathil padhivu seyyunga. Voice idhai innum save pannaadhu.',
          'Please record this on the Sell or accounts screen. Voice does not save it yet.',
        ),
        finished: true,
      );
    }
    return _next();
  }

  /// The owner's reply while a question is open.
  DialogueTurn answer(String text, {bool yes = false, bool no = false}) {
    final intent = _intent;
    if (intent == null) return const DialogueTurn(finished: true);
    _heard.add(text);
    final tokens = voiceTokens(text);
    final asking = _asking;
    switch (asking) {
      case 'confirm':
        if (yes) {
          _confirmed = true;
        } else if (no) {
          reset();
          return const DialogueTurn(
            say: VoiceLine(
              'சரி, சேர்க்கல.',
              'Sari, add pannala.',
              'Okay, not added.',
            ),
            finished: true,
          );
        } else {
          // A correction instead of yes/no: read the slots again.
          _fill(intent, text);
        }
      case 'photo':
        _slots['photoWanted'] = yes;
        if (!yes && !no) _slots['photoWanted'] = false;
      case 'name':
        final name = _nameFrom(tokens);
        if (name != null) _slots['name'] = name;
      case 'age_months':
        final months = ageMonthsIn(tokens) ?? _plainNumber(tokens)?.round();
        _slots['age_months'] = months ?? (_saysUnknown(tokens) ? -1 : null);
      case 'breed':
        String? breed;
        for (final t in tokens) {
          breed ??= _breedKey(t);
        }
        _slots['breed'] = breed ?? (_saysUnknown(tokens) ? 'unknown' : null);
      case 'cow':
        final guesses = guessCows(tokens, cows());
        if (guesses.isNotEmpty && guesses.first.score >= cowMaybeScore) {
          _slots['cow'] = guesses.first.name;
        } else if (_saysUnknown(tokens)) {
          _slots['cow'] = '';
        }
      case 'amount':
        final money = amountsIn(tokens);
        if (money.isNotEmpty) {
          _slots[intent == 'vet_visit' ? 'fee' : 'amount'] = money.last;
        } else if (_saysUnknown(tokens)) {
          _slots[intent == 'vet_visit' ? 'fee' : 'amount'] = 0.0;
        }
      case 'qty':
        final qty = extractLitres(tokens);
        if (qty != null) _slots['qty'] = qty;
      case 'expense_name':
        final words = tokens.where((t) => !_saysUnknown([t])).toList();
        if (words.isNotEmpty) _slots['name'] = words.take(4).join(' ');
    }
    return _next(repeatOf: asking);
  }

  /// The next question, or the action when everything is known.
  DialogueTurn _next({String? repeatOf}) {
    final intent = _intent!;
    final missing = _missingSlot(intent);
    if (missing != null) {
      final repeated = missing == repeatOf;
      _asking = missing;
      return DialogueTurn(say: _question(intent, missing, repeated: repeated));
    }
    if (!_confirmed) {
      _asking = 'confirm';
      return DialogueTurn(say: _confirmLine(intent));
    }
    final action = VoiceAction(intent, {
      ..._slots,
      'heard': _heard.join(' · '),
    });
    final done = _doneLine(intent);
    reset();
    return DialogueTurn(say: done, action: action, finished: true);
  }

  void _fill(String intent, String text) {
    final reading = extraIntent(text, cows: cows());
    if (reading == null) return;
    for (final e in reading.slots.entries) {
      if (e.value != null) _slots[e.key] = e.value;
    }
  }

  String? _missingSlot(String intent) {
    bool unset(String key) => _slots[key] == null;
    switch (intent) {
      case 'add_cow':
        if (unset('name')) return 'name';
        if (!_confirmed) return null; // "create the profile?" comes first
        if (!_slots.containsKey('photoWanted')) return 'photo';
        if (unset('age_months')) return 'age_months';
        if (unset('breed')) return 'breed';
        return null;
      case 'expense':
        if (unset('name')) return 'expense_name';
        if (unset('amount')) return 'amount';
        return null;
      case 'stock_use':
        if (unset('qty')) return 'qty';
        return null;
      case 'stock_in':
        if (unset('qty')) return 'qty';
        if (unset('amount')) return 'amount';
        return null;
      case 'vet_visit':
        if (unset('cow')) return 'cow';
        if (unset('fee')) return 'amount';
        return null;
      case 'vaccination':
      case 'insemination':
      case 'pregnancy_confirmed':
      case 'symptom':
      case 'diagnosis':
      case 'calf_birth':
        if (unset('cow')) return 'cow';
        return null;
    }
    return null;
  }

  String _ta(Object? name) => tamilName('${name ?? ''}');

  VoiceLine _question(String intent, String slot, {bool repeated = false}) {
    final sorry = repeated
        ? const VoiceLine('புரியல. ', 'Puriyala. ', 'Sorry. ')
        : const VoiceLine('', '', '');
    VoiceLine line;
    final name = _slots['name'];
    switch (slot) {
      case 'name':
        line = const VoiceLine(
          'புதிய மாட்டின் பெயர் என்ன?',
          'Pudhu maattin peyar enna?',
          "What is the new cow's name?",
        );
      case 'photo':
        line = VoiceLine(
          '${tamilDativeName(_ta(name))} இப்போது புகைப்படம் எடுக்கவா?',
          '$name-ku ippo photo edukkava?',
          'Shall I take a photo of $name now?',
        );
      case 'age_months':
        line = VoiceLine(
          '${tamilDativeName(_ta(name))} எத்தனை மாத வயசு? தெரியாதுன்னா "தெரியாது" சொல்லுங்க.',
          '$name-ku ethana maasam vayasu?',
          'How old is $name, in months or years? Say "don\'t know" to skip.',
        );
      case 'breed':
        line = const VoiceLine(
          'என்ன இனம்? ஜெர்சி, HF, நாட்டு மாடு, கிர்?',
          'Enna inam? Jersey, HF, naattu maadu?',
          'Which breed? Jersey, HF, native, Gir?',
        );
      case 'cow':
        line = const VoiceLine('எந்த மாடு?', 'Endha maadu?', 'Which cow?');
      case 'amount':
        line = const VoiceLine(
          'எவ்வளவு ரூபாய்?',
          'Evvalavu rupaai?',
          'How many rupees?',
        );
      case 'qty':
        line = const VoiceLine(
          'எவ்வளவு? எத்தனை கிலோ அல்லது மூட்டை?',
          'Evvalavu? Ethana kilo illa moottai?',
          'How much? How many kilos or bags?',
        );
      case 'expense_name':
        line = const VoiceLine(
          'எதற்கான செலவு?',
          'Edhukkaana selavu?',
          'What was the expense for?',
        );
      default:
        line = const VoiceLine(
          'மறுபடியும் சொல்லுங்க.',
          'Marubadiyum sollunga.',
          'Please say it again.',
        );
    }
    return VoiceLine(
      '${sorry.ta}${line.ta}',
      '${sorry.tanglish}${line.tanglish}',
      '${sorry.en}${line.en}',
    );
  }

  VoiceLine _confirmLine(String intent) {
    final s = _slots;
    final cow = s['cow'];
    final cowTa = _ta(cow);
    final amount = _money(s['amount']);
    switch (intent) {
      case 'add_cow':
        final name = s['name'];
        return VoiceLine(
          '${tamilDativeName(_ta(name))} புதிய profile உருவாக்கவா?',
          '$name-ku pudhu profile create pannava?',
          'Shall I create a profile for $name?',
        );
      case 'expense':
        return VoiceLine(
          '${s['name']} $amount ரூபாய் செலவு. சேர்க்கவா?',
          '${s['name']} $amount rupaai selavu. Add pannava?',
          'Expense: ${s['name']}, $amount rupees. Shall I add it?',
        );
      case 'stock_use':
      case 'stock_in':
        final item = s['item'] == 'vaikol'
            ? const ('வைக்கோல்', 'vaikol', 'hay')
            : const ('தவுடு', 'thavudu', 'bran');
        final qty = _qtyWord(s['qty']);
        final unit = _unitWords(s['unit']);
        final used = intent == 'stock_use';
        return VoiceLine(
          '${item.$1} $qty ${unit.$1} ${used ? 'பயன்படுத்தியது' : 'வாங்கியது'}${used ? '' : ', ${_money(s['amount'])} ரூபாய்'}. சேர்க்கவா?',
          '${item.$2} $qty ${unit.$2} ${used ? 'use' : 'vaangiyadhu'}. Add pannava?',
          '${used ? 'Used' : 'Bought'} $qty ${unit.$3} of ${item.$3}${used ? '' : ' for ${_money(s['amount'])} rupees'}. Shall I add it?',
        );
      case 'vet_visit':
        return VoiceLine(
          '${tamilDativeName(cowTa)} டாக்டர் வருகை, ${_money(s['fee'])} ரூபாய். சேர்க்கவா?',
          '$cow-ku doctor visit, ${_money(s['fee'])} rupaai. Add pannava?',
          'Doctor visit for $cow, ${_money(s['fee'])} rupees. Shall I add it?',
        );
      case 'vaccination':
        return VoiceLine(
          '${tamilDativeName(cowTa)} ஊசி போட்டது. சேர்க்கவா?',
          '$cow-ku oosi pottadhu. Add pannava?',
          'Injection for $cow. Shall I add it?',
        );
      case 'insemination':
        return VoiceLine(
          '${tamilDativeName(cowTa)} கருவூட்டல் செய்தது. சேர்க்கவா?',
          '$cow-ku karuvootal. Add pannava?',
          'Insemination for $cow. Shall I add it?',
        );
      case 'pregnancy_confirmed':
        return VoiceLine(
          '$cowTa சினை உறுதி. சேர்க்கவா?',
          '$cow sinai urudhi. Add pannava?',
          '$cow is confirmed pregnant. Shall I add it?',
        );
      case 'symptom':
      case 'diagnosis':
        return VoiceLine(
          '${tamilDativeName(cowTa)} உடல்நிலை குறிப்பு. சேர்க்கவா?',
          '$cow-ku health note. Add pannava?',
          'Health note for $cow. Shall I add it?',
        );
      case 'calf_birth':
        return VoiceLine(
          '$cowTa கன்று ஈன்றது. குறிப்பு சேர்க்கவா?',
          '$cow kanru eenthuchu. Note add pannava?',
          '$cow had a calf. Shall I add a note?',
        );
    }
    return const VoiceLine('சேர்க்கவா?', 'Add pannava?', 'Shall I add it?');
  }

  VoiceLine _doneLine(String intent) {
    if (intent == 'add_cow') {
      final name = _slots['name'];
      final photo = _slots['photoWanted'] == true;
      return VoiceLine(
        '${_ta(name)} profile உருவாக்கினேன்.${photo ? ' புகைப்படத்தை profile-இல் சேர்க்கலாம்.' : ''}',
        '$name profile create panniten.',
        'Created $name\'s profile.${photo ? ' Add the photo on the profile.' : ''}',
      );
    }
    if (intent == 'calf_birth') {
      return const VoiceLine(
        'குறிப்பு சேர்த்தேன். கன்றின் விவரங்களை app-இல் சேர்க்கவும்.',
        'Note add panniten. Kanru details app-la serkkavum.',
        'Note added. Add the calf\'s details in the app.',
      );
    }
    return const VoiceLine('சேர்த்தேன்.', 'Add panniten.', 'Added.');
  }

  static String _money(Object? v) {
    final n = v is num ? v.toDouble() : double.tryParse('$v');
    if (n == null || n <= 0) return '0';
    return n == n.roundToDouble() ? n.toStringAsFixed(0) : n.toStringAsFixed(1);
  }

  static String _qtyWord(Object? v) => _money(v);

  static (String, String, String) _unitWords(Object? unit) => switch (unit) {
    'bag' => ('மூட்டை', 'moottai', 'bags'),
    'bundle' => ('கட்டு', 'kattu', 'bundles'),
    _ => ('கிலோ', 'kilo', 'kg'),
  };

  static String? _breedKey(String token) {
    const map = {
      'jersey': 'jersey',
      'ஜெர்சி': 'jersey',
      'hf': 'hf',
      'holstein': 'hf',
      'gir': 'gir',
      'கிர்': 'gir',
      'sahiwal': 'sahiwal',
      'sindhi': 'sindhi',
      'சிந்தி': 'sindhi',
      'kangayam': 'kangayam',
      'காங்கேயம்': 'kangayam',
      'naatu': 'native',
      'naattu': 'native',
      'நாட்டு': 'native',
      'native': 'native',
      'local': 'native',
    };
    return map[token];
  }

  static double? _plainNumber(List<String> tokens) => extractLitres(tokens);

  static String? _nameFrom(List<String> tokens) {
    for (final t in tokens) {
      if (t.length > 1 &&
          extractLitres([t]) == null &&
          !_unknownWords.contains(t)) {
        return t;
      }
    }
    return null;
  }

  /// Breed for the animal record and its Tamil word.
  static (String, String)? breedName(Object? key) => _breedNames['$key'];
}

/// "லூனா" → "லூனாவுக்கு": the dative form used in VIMO's Tamil sentences.
String tamilDativeName(String name) {
  if (name.isEmpty) return name;
  if (!RegExp(r'[஀-௿]$').hasMatch(name)) return '$name-க்கு';
  if (name.endsWith('்')) return '${name.substring(0, name.length - 1)}ுக்கு';
  if (RegExp('[ிீைெே]\$').hasMatch(name)) return '$nameக்கு';
  return '$nameவுக்கு';
}
