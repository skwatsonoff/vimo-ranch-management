part of 'main.dart';

// =============================================================================
//  On-device learning: what the owner taught VIMO.
//
//  When VIMO mishears, the owner types or says what was meant. The fix is
//  kept in the Hive box `voice_learning` (this phone only) and applied before
//  the next sentence is understood, with no internet and no waiting.
// =============================================================================

const voiceLearningBox = 'voice_learning';

Future<void> openVoiceLearning() async {
  try {
    if (!Hive.isBoxOpen(voiceLearningBox)) await Hive.openBox(voiceLearningBox);
  } catch (_) {}
}

VoiceLexicon? _lexicon;
String? _lexiconScope;

Iterable<(String, Map<String, dynamic>)> _lessonRows() sync* {
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
      from.length > 400 || to.length > 400 || !Hive.isBoxOpen(voiceLearningBox)) {
    return;
  }
  final scope = _voiceScope();
  final prefix = _voicePrefix(scope);
  final pairs = VoiceLexicon().learn(from, to);
  final command = parseVoiceCommand(to, cowNames(), aliases: cowNameAliases());
  final share = scope.isNotEmpty && command.cowIsSure &&
      command.litres != null && command.hasMilkUnit && !command.sale;
  final box = Hive.box(voiceLearningBox);
  await box.putAll({
    '${prefix}text:${from.toLowerCase()}': _makeVoiceLesson(
      box, '${prefix}text:${from.toLowerCase()}', 'text', from, to, share: share,
    ),
    for (final (a, b) in pairs)
      '${prefix}word:${phoneticKey(a)}': _makeVoiceLesson(
        box, '${prefix}word:${phoneticKey(a)}', 'word', a, b,
      ),
  });
  _lexicon = null;
  if (share) _queueDriveSync();
  VoiceDiagnostics.log('learned', {
    'heard': from,
    'meant': to,
    'words': [for (final (a, b) in pairs) '$a → $b'],
  });
}

Map<String, dynamic> _makeVoiceLesson(
  Box box, String key, String kind, String heard, String meant, {
  bool share = false,
  bool deleted = false,
}) {
  final previous = asMap(box.get(key));
  final now = DateTime.now().toUtc();
  return {
    'kind': kind,
    'heard': heard,
    'meant': meant,
    'count': toInt(previous['count']) + 1,
    'updatedAt': now.toIso8601String(),
    'changed': math.max(now.millisecondsSinceEpoch, toInt(previous['changed']) + 1),
    'share': share,
    'deleted': deleted,
  };
}

Future<void> rememberConfirmedMilkCow(String heard, String cow, double litres) async {
  final scope = _voiceScope();
  if (scope.isEmpty || heard.isEmpty || heard.length > 400 ||
      !Hive.isBoxOpen(voiceLearningBox)) return;
  final original = parseVoiceCommand(heard, cowNames(), aliases: cowNameAliases());
  if (original.cowIsSure || original.litres != litres ||
      original.sale || !original.hasMilkUnit) return;
  final box = Hive.box(voiceLearningBox);
  final key = '${_voicePrefix(scope)}example:${heard.toLowerCase()}';
  await box.put(key, _makeVoiceLesson(
    box, key, 'example', heard, '$cow $litres litres', share: true,
  ));
  _lexicon = null;
  _queueDriveSync();
}

/// The owner's fixes applied to a heard sentence.
String voiceRewrite(String text) => voiceLexicon().apply(text);

/// Every lesson, newest first, for the "Learned words" list.
List<Map<String, dynamic>> learnedVoiceRows() {
  final rows = [for (final (key, row) in _lessonRows()) {...row, 'key': key}];
  rows.sort((a, b) => txt(b, 'updatedAt').compareTo(txt(a, 'updatedAt')));
  return rows;
}

Future<void> forgetVoiceLesson(String key) async {
  if (!Hive.isBoxOpen(voiceLearningBox)) return;
  final box = Hive.box(voiceLearningBox);
  final row = asMap(box.get(key));
  if (row['share'] == true) {
    await box.put(key, _makeVoiceLesson(
      box, key, txt(row, 'kind'), '', '', share: true, deleted: true,
    ));
    _queueDriveSync();
  } else {
    await box.delete(key);
  }
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
  final out = <String, List<String>>{};
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
        if (names.isNotEmpty) out['$key'] = names;
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
