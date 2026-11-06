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

/// The owner's lessons, read once from the box and kept until they change.
VoiceLexicon voiceLexicon() {
  final cached = _lexicon;
  if (cached != null) return cached;
  final lexicon = VoiceLexicon();
  if (Hive.isBoxOpen(voiceLearningBox)) {
    for (final raw in Hive.box(voiceLearningBox).values.whereType<Map>()) {
      final row = asMap(raw);
      final heard = txt(row, 'heard');
      final meant = txt(row, 'meant');
      if (heard.isEmpty || meant.isEmpty) continue;
      if (txt(row, 'kind') == 'word') {
        lexicon.words[phoneticKey(heard)] = meant;
      } else {
        lexicon.sentences[heard.toLowerCase()] = meant;
      }
    }
  }
  return _lexicon = lexicon;
}

/// Remembers that VIMO heard [heard] when [corrected] was said: the
/// sentence, and each word that differs (by sound), with how often.
Future<void> rememberVoiceCorrection(String heard, String corrected) async {
  final from = heard.trim();
  final to = corrected.trim();
  if (from.isEmpty || to.isEmpty || from == to) return;
  if (!Hive.isBoxOpen(voiceLearningBox)) return;
  final box = Hive.box(voiceLearningBox);
  final pairs = VoiceLexicon().learn(from, to);
  Future<void> put(String key, String kind, String a, String b) async {
    final old = asMap(box.get(key));
    await box.put(key, {
      'kind': kind,
      'heard': a,
      'meant': b,
      'count': toInt(old['count']) + 1,
      'updatedAt': DateTime.now().toIso8601String(),
    });
  }

  await put('text:${from.toLowerCase()}', 'text', from, to);
  for (final (a, b) in pairs) {
    await put('word:${phoneticKey(a)}', 'word', a, b);
  }
  _lexicon = null;
  VoiceDiagnostics.log('learned', {
    'heard': from,
    'meant': to,
    'words': [for (final (a, b) in pairs) '$a → $b'],
  });
}

/// The owner's fixes applied to a heard sentence.
String voiceRewrite(String text) => voiceLexicon().apply(text);

/// Every lesson, newest first, for the "Learned words" list.
List<Map<String, dynamic>> learnedVoiceRows() {
  if (!Hive.isBoxOpen(voiceLearningBox)) return const [];
  final box = Hive.box(voiceLearningBox);
  final rows = [
    for (final key in box.keys)
      if (box.get(key) is Map) {...asMap(box.get(key)), 'key': '$key'},
  ];
  rows.sort((a, b) => txt(b, 'updatedAt').compareTo(txt(a, 'updatedAt')));
  return rows;
}

Future<void> forgetVoiceLesson(String key) async {
  if (!Hive.isBoxOpen(voiceLearningBox)) return;
  await Hive.box(voiceLearningBox).delete(key);
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

/// Words the recogniser should favour: the wake word, cow names in every
/// spelling, customers, and words the owner taught VIMO.
List<String> voiceHotwords({int limit = 120}) {
  final words = <String>{'Vimo', 'Hey Vimo', 'விமோ'};
  for (final cow in cowNames()) {
    words.add(cow);
    words.add(tamilCowName(cow));
  }
  for (final extra in cowNameAliases().values) {
    words.addAll(extra);
  }
  words.addAll(learnedVoiceWords());
  words.addAll(knownPeopleNames().take(40));
  return words.where((w) => w.trim().isNotEmpty).take(limit).toList();
}

/// Everything the owner taught, as words to favour.
List<String> learnedVoiceWords() {
  if (!Hive.isBoxOpen(voiceLearningBox)) return const [];
  return [
    for (final row in Hive.box(voiceLearningBox).values.whereType<Map>())
      if ('${row['meant'] ?? ''}'.trim().isNotEmpty) '${row['meant']}'.trim(),
  ];
}
