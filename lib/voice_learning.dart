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

/// Remembers that VIMO heard [heard] when [corrected] was said.
Future<void> rememberVoiceCorrection(String heard, String corrected) async {
  final from = heard.trim();
  final to = corrected.trim();
  if (from.isEmpty || to.isEmpty || from == to) return;
  if (!Hive.isBoxOpen(voiceLearningBox)) return;
  final box = Hive.box(voiceLearningBox);
  final key = 'text:${from.toLowerCase()}';
  final old = asMap(box.get(key));
  await box.put(key, {
    'kind': 'text',
    'heard': from,
    'meant': to,
    'count': toInt(old['count']) + 1,
    'updatedAt': DateTime.now().toIso8601String(),
  });
  VoiceDiagnostics.log('learned', {'kind': 'text', 'heard': from, 'meant': to});
}

/// The owner's fixes applied to a heard sentence.
String voiceRewrite(String text) {
  if (!Hive.isBoxOpen(voiceLearningBox)) return text;
  final row = asMap(
    Hive.box(voiceLearningBox).get('text:${text.trim().toLowerCase()}'),
  );
  final meant = txt(row, 'meant');
  return meant.isEmpty ? text : meant;
}

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
