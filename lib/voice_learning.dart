part of 'main.dart';

// =============================================================================
//  On-device learning: what the owner taught VIMO.
//
//  When VIMO mishears, the owner types or says what was meant. The fix is
//  applied at once for this session (memory only). Lasting learning goes to
//  the owner's private Drive after a confirmed save (voice_bridge.dart).
//  Lessons kept on this phone by older versions stay readable until the
//  owner deletes them; nothing new is written to the phone.
// =============================================================================

const voiceLearningBox = 'voice_learning';

Future<void> openVoiceLearning() async {
  try {
    if (!Hive.isBoxOpen(voiceLearningBox)) await Hive.openBox(voiceLearningBox);
  } catch (_) {}
}

VoiceLexicon? _lexicon;
String? _lexiconScope;

/// This session's corrections (memory only, gone when the app closes).
final Map<String, Map<String, dynamic>> _sessionLessons = {};

Iterable<(String, Map<String, dynamic>)> _lessonRows() sync* {
  for (final e in _sessionLessons.entries) {
    yield (e.key, e.value);
  }
  if (!Hive.isBoxOpen(voiceLearningBox)) return;
  final box = Hive.box(voiceLearningBox);
  final prefix = _voicePrefix(_voiceScope());
  for (final key in box.keys.whereType<String>()) {
    // Legacy lessons remain readable on their original device.
    if (!key.startsWith('text:') && !key.startsWith('word:') &&
        (prefix.isEmpty || !key.startsWith(prefix))) {
      continue;
    }
    final row = asMap(box.get(key));
    if (row.isNotEmpty && row['deleted'] != true) yield (key, row);
  }
}

/// The owner's lessons, read once from the box and kept until they change.
VoiceLexicon voiceLexicon() {
  final scope = _voiceScope();
  final cached = _lexicon;
  if (cached != null && _lexiconScope == scope) return cached;
  final lexicon = VoiceLexicon();
  for (final (_, row) in _lessonRows()) {
    final heard = txt(row, 'heard');
    final meant = txt(row, 'meant');
    if (heard.isEmpty || meant.isEmpty) continue;
    if (row['kind'] == 'word') {
      lexicon.words[phoneticKey(heard)] = meant;
    } else if (row['kind'] == 'text') {
      lexicon.sentences[heard.toLowerCase()] = meant;
    }
  }
  _lexiconScope = scope;
  return _lexicon = lexicon;
}

/// Remembers that VIMO heard [heard] when [corrected] was said: the
/// sentence, and each word that differs (by sound), with how often.
Future<void> rememberVoiceCorrection(String heard, String corrected) async {
  final from = heard.trim();
  final to = corrected.trim();
  if (from.isEmpty || to.isEmpty || from == to ||
      from.length > 400 || to.length > 400) {
    return;
  }
  final pairs = VoiceLexicon().learn(from, to);
  final now = DateTime.now().toUtc().toIso8601String();
  Map<String, dynamic> lesson(String kind, String heard, String meant) =>
      {'kind': kind, 'heard': heard, 'meant': meant, 'count': 1, 'updatedAt': now, 'session': true};
  _sessionLessons['session:text:${from.toLowerCase()}'] = lesson('text', from, to);
  for (final (a, b) in pairs) {
    _sessionLessons['session:word:${phoneticKey(a)}'] = lesson('word', a, b);
  }
  _lexicon = null;
  VoiceDiagnostics.log('learned', {
    'heard': from,
    'meant': to,
    'words': pairs.length,
  });
}

/// Confirmed cows are now learned in Drive after the real save
/// (sendVerifiedMilkExample); nothing is written to the phone.
Future<void> rememberConfirmedMilkCow(String heard, String cow, double litres) async {}

/// The owner's fixes applied to a heard sentence.
String voiceRewrite(String text) => voiceLexicon().apply(text);

/// Every lesson, newest first, for the "Learned words" list.
List<Map<String, dynamic>> learnedVoiceRows() {
  final rows = [for (final (key, row) in _lessonRows()) {...row, 'key': key}];
  rows.sort((a, b) => txt(b, 'updatedAt').compareTo(txt(a, 'updatedAt')));
  return rows;
}

Future<void> forgetVoiceLesson(String key) async {
  if (_sessionLessons.remove(key) != null) {
    _lexicon = null;
    return;
  }
  if (!Hive.isBoxOpen(voiceLearningBox)) return;
  final box = Hive.box(voiceLearningBox);
  final row = asMap(box.get(key));
  // Deleting a legacy local lesson removes it from this phone.
  if (row.isNotEmpty) await box.delete(key);
  _lexicon = null;
  VoiceDiagnostics.log('unlearned', {'key': key});
}

/// The lexicon for cloud training: learned words, cow names in every
/// spelling and the dairy words VIMO knows (no people's details).
Map<String, Object?> voiceLexiconExport() => {
  'schema': 1,
  'createdAt': DateTime.now().toIso8601String(),
  'cows': [
    for (final cow in cowNames())
      {
        'name': cow,
        'tamil': tamilCowName(cow),
        'aliases': cowNameAliases()[cow] ?? const [],
      },
  ],
  'learned': [
    for (final row in learnedVoiceRows())
      {
        'kind': txt(row, 'kind'),
        'heard': txt(row, 'heard'),
        'meant': txt(row, 'meant'),
        'count': toInt(row['count']),
      },
  ],
};

// --- lessons from the owner's recordings ---------------------------------------

/// Where the phone keeps the last lessons read from the cloud.
const _cloudLessonsKey = 'voiceCloudLessons';
Map<String, List<String>>? _cloudAliases;

/// Cow names as the owner says them, learned in the cloud from the "Train
/// VIMO" recordings ("Shomperi" heard as "strawberry"): one more name for
/// each cow, so VIMO understands it next time. Works offline from the copy
/// kept on the phone.
Map<String, List<String>> cloudCowAliases() {
  final cached = _cloudAliases;
  if (cached != null) return cached;
  final out = <String, List<String>>{
    // Learned in Drive, loaded for this session only.
    for (final e in VoiceDriveState.aliases.entries) e.key: [...e.value],
  };
  try {
    final raw = Hive.isBoxOpen('settings')
        ? Hive.box('settings').get(_cloudLessonsKey)
        : null;
    final lessons = raw is String ? jsonDecode(raw) : null;
    final aliases = lessons is Map ? lessons['aliases'] : null;
    if (aliases is Map) {
      for (final MapEntry(:key, :value) in aliases.entries) {
        if (value is! List) continue;
        final names = [
          for (final v in value)
            if ('$v'.trim().isNotEmpty) '$v'.trim(),
        ];
        if (names.isNotEmpty) out['$key'] = [...?out['$key'], ...names];
      }
    }
  } catch (_) {}
  return _cloudAliases = out;
}

/// Words the recogniser should favour: the wake word, cow names in every
/// spelling, customers, and words the owner taught VIMO.
List<String> voiceHotwords({int limit = 120}) {
  final words = <String>{'Vimo', 'Hey Vimo', 'விமோ'};
  for (final cow in cowNames()) {
    words.add(cow);
    words.add(tamilCowName(cow));
  }
  // Real names only: a learned mishearing ("strawberry") is understood,
  // never favoured.
  for (final extra in cowNameAliases(learned: false).values) {
    words.addAll(extra);
  }
  words.addAll(learnedVoiceWords());
  words.addAll(knownPeopleNames().take(40));
  return words.where((w) => w.trim().isNotEmpty).take(limit).toList();
}

/// Everything the owner taught, as words to favour.
List<String> learnedVoiceWords() => [
  for (final (_, row) in _lessonRows())
    if (row['kind'] != 'example' && txt(row, 'meant').trim().isNotEmpty)
      txt(row, 'meant').trim(),
];

MilkRecognitionModel? _milkModel;
VoiceLexicon? _milkModelLexicon;
String? _milkModelCows;

MilkRecognitionModel milkRecognitionModel() {
  final lexicon = voiceLexicon();
  final cows = cowNames();
  final aliases = cowNameAliases();
  final fingerprint = jsonEncode([cows, aliases]);
  final cached = _milkModel;
  if (cached != null && identical(lexicon, _milkModelLexicon) &&
      fingerprint == _milkModelCows) return cached;
  _milkModelLexicon = lexicon;
  _milkModelCows = fingerprint;
  return _milkModel = MilkRecognitionModel.train([
    ...lexicon.sentences.entries.map((entry) => (entry.key, entry.value)),
    for (final (_, row) in _lessonRows())
      if (row['kind'] == 'example') (txt(row, 'heard'), txt(row, 'meant')),
  ], cows, aliases: aliases);
}
