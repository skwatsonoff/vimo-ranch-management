/// Pure helpers for "Train VIMO": the sentences the owner reads, the WAV
/// file format, and recording targets. No Flutter, no storage: tested in
/// test/voice_training_test.dart.
library;

import 'dart:convert';
import 'dart:typed_data';

/// Recording targets per language, in minutes (Tamil 2 h, Tanglish 1 h,
/// English 30 min).
const trainingTargetsMinutes = {'ta': 120.0, 'ta-Latn': 60.0, 'en': 30.0};

/// A sentence to read aloud.
class TrainingPrompt {
  final String text;
  final String language;
  const TrainingPrompt(this.text, this.language);
}

/// Dairy sentences with the ranch's own [cows] (Tamil names in
/// [tamilNames]), litres, expenses, questions and numbers, in Tamil script,
/// Tanglish and English. The same list for the same ranch, so progress can
/// continue where it stopped.
List<TrainingPrompt> trainingPrompts(
  List<String> cows, {
  Map<String, String> tamilNames = const {},
}) {
  final names = cows.isEmpty ? const ['Lakshmi', 'Kaveri', 'Rani'] : cows;
  final out = <TrainingPrompt>[];
  const litres = [
    ('5', 'அஞ்சு', 'anju', 'five'),
    ('2.5', 'ரெண்டரை', 'rendara', 'two and a half'),
    ('8', 'எட்டு', 'ettu', 'eight'),
    ('3', 'மூணு', 'moonu', 'three'),
    ('10', 'பத்து', 'pathu', 'ten'),
    ('1.5', 'ஒன்றரை', 'onnara', 'one and a half'),
    ('6', 'ஆறு', 'aaru', 'six'),
    ('12', 'பன்னிரண்டு', 'pannendu', 'twelve'),
  ];
  for (int i = 0; i < names.length; i++) {
    final cow = names[i];
    final ta = tamilNames[cow] ?? cow;
    final l = litres[i % litres.length];
    final m = litres[(i + 3) % litres.length];
    out
      ..add(TrainingPrompt('ஹே விமோ, $ta ${l.$2} லிட்டர்', 'ta'))
      ..add(
        TrainingPrompt('இன்று காலை $ta ${m.$1} லிட்டர் பால் கொடுத்தது', 'ta'),
      )
      ..add(
        TrainingPrompt(
          '${cow.toLowerCase()} ku ${l.$3} litre add pannu',
          'ta-Latn',
        ),
      )
      ..add(
        TrainingPrompt(
          'nethu maalai ${cow.toLowerCase()} ${m.$3} litre kuduthuchu',
          'ta-Latn',
        ),
      )
      ..add(TrainingPrompt('add ${l.$4} litres for $cow', 'en'))
      ..add(TrainingPrompt('$ta மாட்டுக்கு ஊசி போட்டேன்', 'ta'))
      ..add(TrainingPrompt('$ta சினை உறுதி ஆனது', 'ta'))
      ..add(TrainingPrompt('${cow.toLowerCase()} maadu nondukuthu', 'ta-Latn'))
      ..add(TrainingPrompt('how much milk did $cow give this month', 'en'));
  }
  const general = [
    TrainingPrompt('கயிறு 150 ரூபாய் செலவு', 'ta'),
    TrainingPrompt('பெட்ரோல் 300 ரூபாய்', 'ta'),
    TrainingPrompt('தவுடு 2 மூட்டை பயன்படுத்தினேன்', 'ta'),
    TrainingPrompt('வைக்கோல் 20 கட்டு வாங்கினேன்', 'ta'),
    TrainingPrompt('இன்று எவ்வளவு பால்?', 'ta'),
    TrainingPrompt('இந்த மாதம் மொத்தம் எவ்வளவு பால்?', 'ta'),
    TrainingPrompt('டாக்டர் வந்தார் 500 ரூபாய்', 'ta'),
    TrainingPrompt('5 இல்லை 6 லிட்டர்', 'ta'),
    TrainingPrompt('கடைசி பதிவை நீக்கு', 'ta'),
    TrainingPrompt('பால் கறந்து முடிச்சிட்டேன்', 'ta'),
    TrainingPrompt('ஒன்று இரண்டு மூன்று நான்கு ஐந்து', 'ta'),
    TrainingPrompt('ஆறு ஏழு எட்டு ஒன்பது பத்து', 'ta'),
    TrainingPrompt('இருபது முப்பது நாற்பது ஐம்பது நூறு', 'ta'),
    TrainingPrompt('அரை கால் முக்கால் ஒன்றரை ரெண்டரை', 'ta'),
    TrainingPrompt('thavudu anju kilo potten', 'ta-Latn'),
    TrainingPrompt('petrol ku 200 rupaai selavu', 'ta-Latn'),
    TrainingPrompt('innaiku ethana litre paal', 'ta-Latn'),
    TrainingPrompt('Luna nu pudhu maadu vaangunom', 'ta-Latn'),
    TrainingPrompt('onnu rendu moonu naalu anju', 'ta-Latn'),
    TrainingPrompt('aaru ezhu ettu ombodhu pathu', 'ta-Latn'),
    TrainingPrompt('mudinchu, save pannu', 'ta-Latn'),
    TrainingPrompt('bought twenty five kilos of bran', 'en'),
    TrainingPrompt('the doctor checked the cow today', 'en'),
    TrainingPrompt('remove the last entry', 'en'),
    TrainingPrompt('one two three four five six seven eight nine ten', 'en'),
  ];
  out.addAll(general);
  return out;
}

/// 16-bit mono PCM as a WAV file (the 44-byte RIFF header plus the data).
Uint8List wavFromPcm16(Uint8List pcm, {int sampleRate = 16000}) {
  final header = ByteData(44);
  void ascii(int at, String s) {
    for (int i = 0; i < s.length; i++) {
      header.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  header.setUint32(4, 36 + pcm.length, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  header.setUint32(16, 16, Endian.little); // PCM chunk size
  header.setUint16(20, 1, Endian.little); // PCM
  header.setUint16(22, 1, Endian.little); // mono
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, sampleRate * 2, Endian.little); // bytes per second
  header.setUint16(32, 2, Endian.little); // block align
  header.setUint16(34, 16, Endian.little); // bits per sample
  ascii(36, 'data');
  header.setUint32(40, pcm.length, Endian.little);
  return Uint8List.fromList([...header.buffer.asUint8List(), ...pcm]);
}

/// Length of 16 kHz 16-bit mono [pcmBytes] in milliseconds.
int pcmDurationMs(int pcmBytes, {int sampleRate = 16000}) =>
    (pcmBytes * 1000 / (sampleRate * 2)).round();

/// Minutes recorded per language from recording rows ({lang, durationMs}).
Map<String, double> minutesByLanguage(Iterable<Map<String, Object?>> rows) {
  final out = <String, double>{};
  for (final r in rows) {
    final lang = '${r['lang'] ?? ''}';
    final ms = r['durationMs'];
    if (lang.isEmpty || ms is! num) continue;
    out[lang] = (out[lang] ?? 0) + ms / 60000;
  }
  return out;
}

/// The JSON sidecar uploaded next to each WAV: what was said and how.
/// Speaker is only a tag the owner chose ("Appa", "worker 1"); no names of
/// people go into file paths.
String trainingSidecar({
  required String id,
  required String transcript,
  required String language,
  required String speaker,
  required String noise,
  required int durationMs,
  required String device,
  required DateTime recordedAt,
}) => jsonEncode({
  'schema': 1,
  'id': id,
  'transcript': transcript,
  'language': language,
  'speaker': speaker,
  'noise': noise,
  'durationMs': durationMs,
  'sampleRate': 16000,
  'device': device,
  'recordedAt': recordedAt.toUtc().toIso8601String(),
});

/// Longest recording kept: one Firestore document holds at most 1 MiB,
/// and 25 seconds of 16 kHz mono WAV is about 800 KB.
const trainingMaxSeconds = 25;

/// Firestore id of an uploaded recording: the owner's uid, then the id, so
/// the rules can check whose it is. No names of people are in it.
String trainingDocId(String uid, String id) => '${uid}_$id';

/// Firestore collections the training uses (free Spark plan; no Storage).
const trainingAudioCollection = 'voice_training_audio';
const trainingLexiconCollection = 'voice_training_lexicon';

/// What the cloud learned from the recordings, read by the phone.
const trainingLessonsCollection = 'voice_training_lessons';

/// Status words written by the cloud workflow, in order.
const trainingStatuses = [
  'requested',
  'running',
  'evaluating',
  'packaging',
  'ready',
  'failed',
];

/// True when a finished job's model is better (lower word error rate) than
/// the one before, so it may be installed. A worse model is never offered.
bool trainingImproved(Map<String, Object?> job) {
  if (job['status'] != 'ready') return false;
  final wer = job['wer'];
  final previous = job['previousWer'];
  if (wer is! num) return false;
  if (previous is! num) return true;
  return wer < previous;
}
