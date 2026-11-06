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
