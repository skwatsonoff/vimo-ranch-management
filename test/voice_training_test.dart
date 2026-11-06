import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ranch_management/voice_training_core.dart';
import 'package:ranch_management/voice_understanding.dart';

void main() {
  test('prompts use the ranch cows in Tamil, Tanglish and English', () {
    final prompts = trainingPrompts(
      ['Maina', 'Ponni'],
      tamilNames: {'Maina': 'மைனா', 'Ponni': 'பொன்னி'},
    );
    expect(prompts.map((p) => p.language).toSet(), {'ta', 'ta-Latn', 'en'});
    expect(prompts.any((p) => p.text.contains('மைனா')), isTrue);
    expect(prompts.any((p) => p.text.contains('ponni ku')), isTrue);
    expect(prompts.length, greaterThan(40));
    // Every milk prompt is one VIMO itself understands.
    final milk = prompts.where(
      (p) => p.text.contains('லிட்டர்') && p.text.contains('மைனா'),
    );
    for (final p in milk) {
      final r = understandVoice(p.text, cows: const ['Maina', 'Ponni']);
      expect(r.intent, 'milk_record', reason: p.text);
    }
  });

  test('WAV header is valid 16 kHz mono 16-bit', () {
    final pcm = Uint8List(32000); // one second
    final wav = wavFromPcm16(pcm);
    final b = ByteData.sublistView(wav);
    expect(ascii.decode(wav.sublist(0, 4)), 'RIFF');
    expect(ascii.decode(wav.sublist(8, 12)), 'WAVE');
    expect(b.getUint32(4, Endian.little), 36 + pcm.length);
    expect(b.getUint16(22, Endian.little), 1);
    expect(b.getUint32(24, Endian.little), 16000);
    expect(b.getUint16(34, Endian.little), 16);
    expect(b.getUint32(40, Endian.little), pcm.length);
    expect(wav.length, 44 + pcm.length);
    expect(pcmDurationMs(pcm.length), 1000);
  });

  test('minutes per language add up', () {
    final m = minutesByLanguage([
      {'lang': 'ta', 'durationMs': 90000},
      {'lang': 'ta', 'durationMs': 30000},
      {'lang': 'en', 'durationMs': 60000},
      {'lang': '', 'durationMs': 1000},
    ]);
    expect(m, {'ta': 2.0, 'en': 1.0});
  });

  test('sidecar and path carry no personal names', () {
    final json =
        jsonDecode(
              trainingSidecar(
                id: 'r1',
                transcript: 'மைனா 5 லிட்டர்',
                language: 'ta',
                speaker: 'Appa',
                noise: 'quiet',
                durationMs: 2100,
                device: 'android',
                recordedAt: DateTime.utc(2026, 11, 6),
              ),
            )
            as Map;
    expect(json['transcript'], 'மைனா 5 லிட்டர்');
    expect(json['sampleRate'], 16000);
    expect(trainingDocId('uid1', 'r1'), 'uid1_r1');
    expect(trainingMaxSeconds * 32000 + 44, lessThan(1000000));
  });

  test('a worse model is never offered', () {
    expect(
      trainingImproved({'status': 'ready', 'wer': .2, 'previousWer': .3}),
      isTrue,
    );
    expect(
      trainingImproved({'status': 'ready', 'wer': .35, 'previousWer': .3}),
      isFalse,
    );
    expect(trainingImproved({'status': 'ready', 'wer': .3}), isTrue);
    expect(trainingImproved({'status': 'running', 'wer': .1}), isFalse);
    expect(trainingImproved({'status': 'ready'}), isFalse);
  });
}
