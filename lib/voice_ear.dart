/// VIMO's own ear: a Whisper model that runs in the phone's browser
/// (web/vimo_ear.js), for where the browser's speech service cannot help:
/// Tamil on an iPhone (Apple's service has no Tamil) and the Home Screen
/// web app (Apple blocks the service there altogether).
///
/// The model downloads once and stays in the browser's cache; after that
/// listening needs no internet. Speech is found and cut by the ear itself,
/// and each finished sentence comes back as one final [VoiceHeard].
library;

import 'dart:async';

import 'voice_ear_stub.dart'
    if (dart.library.js_interop) 'voice_ear_web.dart'
    as js;
import 'voice_engine.dart';

/// A model the ear can use, and roughly how much it downloads.
class EarModel {
  final String id;
  final int megabytes;
  const EarModel(this.id, this.megabytes);
}

/// Tamil (and Tanglish): Whisper fine-tuned on Tamil by SPRING Lab, IIT
/// Madras, built for the browser by .github/workflows/voice-model-build.yml.
const tamilEarModel = EarModel('whisper-tamil-small', 290);

/// English: Cactus Compute's 17 MB "Whistle" (Apache-2.0), fast, and told
/// the cows' names so it hears them right.
const englishEarModel = EarModel('cactus:whistle', 18);

/// Every other language: OpenAI's multilingual Whisper base.
const otherEarModel = EarModel('onnx-community/whisper-base', 80);

EarModel earModelFor(String locale) => locale.startsWith('ta')
    ? tamilEarModel
    : locale.startsWith('en')
    ? englishEarModel
    : otherEarModel;

/// Whisper's name for the language of [locale].
String earLanguageFor(String locale) => switch (locale.split('-').first) {
  'ta' => 'tamil',
  'hi' => 'hindi',
  'te' => 'telugu',
  'kn' => 'kannada',
  'ml' => 'malayalam',
  'mr' => 'marathi',
  'gu' => 'gujarati',
  'pa' => 'punjabi',
  'bn' => 'bengali',
  _ => 'english',
};

/// Whether this browser can run the ear at all.
bool get earSupported => js.earSupported();

/// Whether [model] is already downloaded.
Future<bool> earDownloaded(EarModel model) => js.earCached(model.id);

/// The ear for [locale] that can be had right now: VIMO's own Tamil model
/// when it is published (or already downloaded), else the multilingual one.
Future<EarModel> earModelReadyFor(String locale) async {
  final best = earModelFor(locale);
  if (best != tamilEarModel) return best;
  if (await js.earCached(best.id) || await js.earAvailable(best.id)) {
    return best;
  }
  return otherEarModel;
}

/// Downloads (once) and loads [model]; [onProgress] gets 0..1.
Future<void> prepareEar(EarModel model, void Function(double) onProgress) =>
    js.earPrepare(model.id, onProgress);

/// Statuses the ear adds while it writes down a sentence.
const earThinking = 'thinking';
const earThought = 'thought';

/// [VoiceEngine] for the ear.
class BrowserEarEngine implements VoiceEngine {
  BrowserEarEngine(this.model);

  final EarModel model;
  final _results = StreamController<VoiceHeard>.broadcast();
  final _levels = StreamController<double>.broadcast();
  final _errors = StreamController<VoiceEngineError>.broadcast();
  final _statuses = StreamController<String>.broadcast();
  bool _listening = false;
  bool _closed = false;

  @override
  final Map<String, Object?> facts = {'engine': 'vimo-ear'};

  @override
  String get name => 'vimo-ear';
  @override
  bool get isOffline => true;
  @override
  bool get isListening => _listening;

  @override
  Future<bool> initialize() async {
    if (!earSupported) return false;
    try {
      await js.earPrepare(model.id, (_) {});
      facts['model'] = model.id;
      return true;
    } catch (error) {
      facts['error'] = '$error';
      return false;
    }
  }

  @override
  Future<List<String>> supportedLocales() async => const [];

  @override
  Future<void> start({
    required String locale,
    List<String> hotwords = const [],
    Duration pauseFor = const Duration(seconds: 12),
    Duration listenFor = const Duration(seconds: 55),
  }) async {
    if (_closed || _listening) return;
    try {
      await js.earStart(
        model.id,
        earLanguageFor(locale),
        keywords: hotwords
            .where(
              (w) =>
                  !w.contains(',') &&
                  w.trim().isNotEmpty &&
                  // Whistle knows Latin letters only.
                  (model != englishEarModel ||
                      RegExp(r"^[A-Za-z][A-Za-z .'-]*$").hasMatch(w.trim())),
            )
            .take(60)
            .join(','),
        onText: (text, ms, seconds) {
          facts['lastMs'] = ms;
          facts['lastSeconds'] = seconds;
          if (!_closed && text.trim().isNotEmpty) {
            _results.add(VoiceHeard(text.trim(), isFinal: true));
          }
        },
        onLevel: (level) {
          if (!_closed) _levels.add(level);
        },
        onError: (code) {
          if (!_closed) _errors.add(VoiceEngineError(code));
        },
        // Whisper needs a few seconds on a phone: the screen says so.
        onThinking: (on) {
          if (!_closed) _statuses.add(on ? earThinking : earThought);
        },
      );
      _listening = true;
      _statuses.add(VoiceStatus.listening);
    } catch (error) {
      final text = '$error';
      _errors.add(
        VoiceEngineError(
          text.contains('NotAllowed') || text.contains('Permission')
              ? 'not-allowed'
              : text.contains('suspended')
              ? 'audio-suspended'
              : 'audio-capture',
          permanent: true,
        ),
      );
      _statuses.add(VoiceStatus.notListening);
    }
  }

  @override
  void changePauseFor(Duration pause) {}

  void _quiet() {
    js.earPause();
    if (!_listening || _closed) return;
    _listening = false;
    _statuses.add(VoiceStatus.notListening);
  }

  @override
  Future<void> stop() async => _quiet();

  @override
  Future<void> cancel() async => _quiet();

  @override
  Stream<VoiceHeard> get results => _results.stream;
  @override
  Stream<double> get soundLevels => _levels.stream;
  @override
  Stream<VoiceEngineError> get errors => _errors.stream;
  @override
  Stream<String> get statuses => _statuses.stream;

  @override
  Future<void> dispose() async {
    _closed = true;
    js.earClose();
    await _results.close();
    await _levels.close();
    await _errors.close();
    await _statuses.close();
  }
}
