import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ranch_management/voice_asr_remote.dart';
import 'package:ranch_management/voice_capture.dart';

class FakeAsr implements SpeechToTextService {
  final List<Completer<String?>> calls = [];
  bool ready = true;
  @override
  String get name => 'fake';
  @override
  bool get configured => ready;
  @override
  Future<String?> transcribe(Uint8List wav,
      {required String locale, List<String> hints = const []}) {
    final c = Completer<String?>();
    calls.add(c);
    return c.future;
  }
}

void main() {
  late FakeCaptureBackend mic;
  late FakeAsr asr;
  late VoiceCaptureController voice;
  late List<String> heard;
  late List<Map<String, Object?>> logs;

  setUp(() {
    mic = FakeCaptureBackend();
    asr = FakeAsr();
    heard = [];
    logs = [];
    voice = VoiceCaptureController(
      backend: mic,
      speechToText: asr,
      locale: 'ta-IN',
      log: (t, d) => logs.add({'type': t, ...d}),
    );
    voice.transcripts.listen(heard.add);
  });
  tearDown(() => voice.dispose());

  test('a tap opens the mic synchronously; listening only after ready', () async {
    final gen = voice.startFromTap();
    expect(mic.calls, ['start:$gen']);
    expect(voice.phase, CapturePhase.connecting);
    await pumpEventQueue();
    expect(voice.phase, CapturePhase.connecting, reason: 'permission alone is not listening');
    mic.ready();
    await pumpEventQueue();
    expect(voice.phase, CapturePhase.listening);
  });

  test('a sentence is written down and handed to the dialogue', () async {
    final gen = voice.startFromTap();
    mic.ready();
    await pumpEventQueue();
    mic.speak(gen);
    expect(voice.phase, CapturePhase.processing);
    asr.calls.single.complete('கண்மணி அஞ்சு லிட்டர்');
    await pumpEventQueue();
    expect(heard, ['கண்மணி அஞ்சு லிட்டர்']);
    expect(voice.phase, CapturePhase.listening);
    // Diagnostics never carry the words.
    expect(jsonEncode(logs), isNot(contains('கண்மணி')));
  });

  test('refused, blocked, busy, no frames and muted are told apart', () async {
    for (final (code, error) in [
      ('not-allowed', CaptureError.denied),
      ('not-allowed:blocked', CaptureError.blocked),
      ('audio-busy', CaptureError.busy),
      ('no-frames', CaptureError.noFrames),
      ('muted', CaptureError.muted),
      ('policy-blocked', CaptureError.unsupported),
    ]) {
      voice.startFromTap();
      mic.fail(code);
      await pumpEventQueue();
      expect(voice.phase, CapturePhase.error, reason: code);
      expect(voice.error, error, reason: code);
    }
  });

  test('Safari needs one more tap: needsTap, then resumeAudio on that tap', () async {
    final gen = voice.startFromTap();
    mic.fail('needs-gesture');
    await pumpEventQueue();
    expect(voice.phase, CapturePhase.needsTap);
    expect(voice.startFromTap(), gen);
    expect(mic.calls.last, 'resumeAudio:$gen');
    mic.ready();
    await pumpEventQueue();
    expect(voice.phase, CapturePhase.listening);
  });

  test('double tap: only the newest start counts', () async {
    final first = voice.startFromTap();
    final firstStart = mic.pendingStart!;
    final second = voice.startFromTap();
    expect(second, greaterThan(first));
    firstStart.completeError(const CaptureFailure('cancelled'));
    await pumpEventQueue();
    expect(voice.phase, CapturePhase.connecting);
    mic.ready();
    await pumpEventQueue();
    expect(voice.phase, CapturePhase.listening);
    expect(voice.generation, second);
  });

  test('interruption drops the late transcript and needs an explicit resume', () async {
    final gen = voice.startFromTap();
    mic.ready();
    await pumpEventQueue();
    mic.speak(gen);
    mic.emit(CapturePhaseEvent(gen, 'interrupted', reason: 'audio-session-interrupted'));
    expect(voice.phase, CapturePhase.interrupted);
    expect(voice.interruption!.isCall, isFalse, reason: 'a browser cannot know it is a call');
    asr.calls.single.complete('கண்மணி அஞ்சு லிட்டர்');
    await pumpEventQueue();
    expect(heard, isEmpty, reason: 'late ASR result after interruption');
    expect(logs.any((l) => l['type'] == 'asr_late_dropped'), isTrue);
    // Events of the old session do nothing.
    mic.speak(gen);
    expect(asr.calls.length, 1);
    // Nothing restarts by itself.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(mic.calls.where((c) => c.startsWith('start:')).length, 1);
    // Resume is a new tap and a new generation.
    final next = voice.startFromTap();
    expect(next, greaterThan(gen));
    mic.ready();
    await pumpEventQueue();
    expect(voice.phase, CapturePhase.listening);
  });

  test('app lifecycle pause interrupts and releases the mic', () async {
    final gen = voice.startFromTap();
    mic.ready();
    await pumpEventQueue();
    voice.interrupt(const CaptureInterruption('lifecycle-paused'));
    expect(mic.calls.last, 'stop:$gen:interrupt-lifecycle-paused');
    expect(voice.phase, CapturePhase.interrupted);
    voice.interrupt(const CaptureInterruption('again'));
    expect(mic.calls.where((c) => c.startsWith('stop')).length, 1);
  });

  test('VIMO speaking gates input, and only the same session listens again', () async {
    final gen = voice.startFromTap();
    mic.ready();
    await pumpEventQueue();
    voice.beginSpeaking();
    expect(mic.calls.last, 'gate:$gen:true');
    expect(voice.phase, CapturePhase.speaking);
    voice.endSpeaking();
    expect(mic.calls.last, 'gate:$gen:false');
    voice.beginSpeaking();
    voice.stop();
    voice.endSpeaking(); // a late TTS completion after Stop
    expect(voice.phase, CapturePhase.stopped);
    expect(mic.calls.last, startsWith('stop:'));
  });

  test('no speech service: no mic is opened, the screen says unavailable', () async {
    asr.ready = false;
    voice.startFromTap();
    expect(mic.calls, isEmpty);
    expect(voice.error, CaptureError.recognitionUnavailable);
  });

  test('speech service quota or outage stops capture, never retries', () async {
    final gen = voice.startFromTap();
    mic.ready();
    await pumpEventQueue();
    mic.speak(gen);
    asr.calls.single.completeError(const SpeechServiceFailure(CaptureError.quota));
    await pumpEventQueue();
    expect(voice.phase, CapturePhase.error);
    expect(voice.error, CaptureError.quota);
    expect(mic.calls.last, 'stop:$gen:asr-quota');
    mic.speak(gen);
    expect(asr.calls.length, 1);
  });

  test('a stuck start times out', () async {
    final v = VoiceCaptureController(
      backend: mic,
      speechToText: asr,
      locale: 'ta-IN',
      startTimeout: const Duration(milliseconds: 30),
    );
    v.startFromTap();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(v.phase, CapturePhase.error);
    expect(v.error, CaptureError.timeout);
    await v.dispose();
  });

  group('VIMO runner client', () {
    Uint8List wav() => Uint8List(44 + 3200);

    test('only https endpoints without query or credentials', () {
      expect(vimoAsrEndpoint(''), isNull);
      expect(vimoAsrEndpoint('http://x.example'), isNull);
      expect(vimoAsrEndpoint('https://u:p@x.example'), isNull);
      expect(vimoAsrEndpoint('https://x.example/?k=1'), isNull);
      expect(vimoAsrEndpoint('https://x.example/asr').toString(),
          'https://x.example/asr/v1/transcribe');
    });

    test('sends the ID token and audio, no-store, and reads the schema', () async {
      late http.Request seen;
      final client = MockClient((r) async {
        seen = r;
        return http.Response(
            jsonEncode({'schema': 'vimo.asr.v1', 'text': ' கண்மணி அஞ்சு '}), 200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      });
      final asr = RemoteSpeechToText(
        endpoint: vimoAsrEndpoint('https://asr.example'),
        idToken: () async => 'tok',
        ranchId: () => 'ranch1',
        client: client,
      );
      expect(await asr.transcribe(wav(), locale: 'ta-IN'), 'கண்மணி அஞ்சு');
      expect(seen.headers['Authorization'], 'Bearer tok');
      expect(seen.headers['Cache-Control'], 'no-store');
      expect(seen.url.query, isEmpty, reason: 'nothing sensitive in the URL');
    });

    test('signed out, 429 and malformed replies fail safe', () async {
      RemoteSpeechToText make(http.Response r, {String? token = 'tok'}) =>
          RemoteSpeechToText(
            endpoint: vimoAsrEndpoint('https://asr.example'),
            idToken: () async => token,
            ranchId: () => 'r',
            client: MockClient((_) async => r),
          );
      await expectLater(
          make(http.Response('', 200), token: null).transcribe(wav(), locale: 'ta'),
          throwsA(isA<SpeechServiceFailure>()));
      await expectLater(
          make(http.Response('', 429)).transcribe(wav(), locale: 'ta'),
          throwsA(predicate((e) => e is SpeechServiceFailure && e.error == CaptureError.quota)));
      expect(await make(http.Response('{"text":"x"}', 200)).transcribe(wav(), locale: 'ta'), isNull);
      expect(await make(http.Response('not json', 200)).transcribe(wav(), locale: 'ta'), isNull);
    });

    test('not configured: zero network calls', () async {
      var calls = 0;
      final asr = RemoteSpeechToText(
        endpoint: null,
        idToken: () async => 'tok',
        ranchId: () => 'r',
        client: MockClient((_) async {
          calls++;
          return http.Response('', 200);
        }),
      );
      expect(asr.configured, isFalse);
      await expectLater(asr.transcribe(wav(), locale: 'ta'), throwsA(isA<SpeechServiceFailure>()));
      expect(calls, 0);
    });
  });
}
