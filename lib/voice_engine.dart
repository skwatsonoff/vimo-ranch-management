/// The ear of VIMO: something that turns speech into text.
///
/// [SystemSpeechEngine] uses the phone's (or browser's) own speech service;
/// it is today's behaviour and always the fallback. [OfflineSpeechEngine]
/// will use a downloaded VIMO model on the phone; until its native runtime
/// is built in, starting it throws [UnsupportedError] and
/// [createVoiceEngine] falls back to the system engine.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text_platform_interface/speech_to_text_platform_interface.dart';

/// Words heard so far in one sentence.
class VoiceHeard {
  final String text;
  final List<String> alternatives;
  final double? confidence;
  final bool isFinal;
  const VoiceHeard(
    this.text, {
    this.alternatives = const [],
    this.confidence,
    this.isFinal = false,
  });
}

class VoiceEngineError {
  final String code;
  final bool permanent;
  const VoiceEngineError(this.code, {this.permanent = false});
}

/// Status words, the same for every engine.
abstract final class VoiceStatus {
  static const listening = 'listening';
  static const notListening = 'notListening';
  static const done = 'done';
}

abstract class VoiceEngine {
  /// "system" or "offline", for the diagnostics log.
  String get name;
  bool get isOffline;
  bool get isListening;

  Future<bool> initialize();
  Future<List<String>> supportedLocales();

  /// Starts one listening session. [hotwords] are names and words to
  /// favour (cow names, customers, the owner's learned words).
  Future<void> start({
    required String locale,
    List<String> hotwords = const [],
    Duration pauseFor = const Duration(seconds: 12),
    Duration listenFor = const Duration(seconds: 55),
  });

  /// Shortens or lengthens the silence that ends the session.
  void changePauseFor(Duration pause);

  Future<void> stop();
  Future<void> cancel();

  Stream<VoiceHeard> get results;
  Stream<double> get soundLevels;
  Stream<VoiceEngineError> get errors;
  Stream<String> get statuses;

  /// Facts for the log, written after [initialize] and [start].
  Map<String, Object?> get facts;

  Future<void> dispose();
}

/// The phone's own speech service through speech_to_text.
class SystemSpeechEngine implements VoiceEngine {
  SystemSpeechEngine([SpeechToText? stt]) : _stt = stt ?? SpeechToText();

  final SpeechToText _stt;
  final _results = StreamController<VoiceHeard>.broadcast();
  final _levels = StreamController<double>.broadcast();
  final _errors = StreamController<VoiceEngineError>.broadcast();
  final _statuses = StreamController<String>.broadcast();
  List<String> _locales = const [];
  final Map<String, bool> _onDevice = {};
  @override
  final Map<String, Object?> facts = {};

  @override
  String get name => 'system';
  @override
  bool get isOffline => false;
  @override
  bool get isListening => _stt.isListening;

  void _status(String s) => _statuses.add(s);
  void _error(SpeechRecognitionError e) =>
      _errors.add(VoiceEngineError(e.errorMsg, permanent: e.permanent));

  @override
  Future<bool> initialize() async {
    final ok = await _stt.initialize(
      onStatus: _status,
      onError: _error,
      finalTimeout: const Duration(milliseconds: 900),
    );
    // speech_to_text is one shared object that binds its callbacks only
    // the first time: point them at this engine every time.
    _stt.statusListener = _status;
    _stt.errorListener = _error;
    facts['initialized'] = ok;
    return ok;
  }

  @override
  Future<List<String>> supportedLocales() async {
    if (_locales.isNotEmpty) return _locales;
    try {
      _locales = [for (final l in await _stt.locales()) l.localeId];
    } catch (_) {
      _locales = const [];
    }
    facts['locales'] = _locales.length;
    return _locales;
  }

  /// The phone's own spelling of [locale] ("ta_IN" or "ta-IN"), so Tamil is
  /// found however the phone writes it.
  String preferredLocale(String locale) {
    final want = locale.toLowerCase().replaceAll('_', '-');
    for (final id in _locales) {
      if (id.toLowerCase().replaceAll('_', '-') == want) return id;
    }
    return locale;
  }

  Future<bool> _hasOnDevice(String locale) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    final known = _onDevice[locale];
    if (known != null) return known;
    var supported = false;
    try {
      supported = await SpeechToTextPlatform.instance.hasOnDeviceSupport(
        localeId: locale,
      );
    } catch (_) {}
    return _onDevice[locale] = supported;
  }

  @override
  Future<void> start({
    required String locale,
    List<String> hotwords = const [],
    Duration pauseFor = const Duration(seconds: 12),
    Duration listenFor = const Duration(seconds: 55),
  }) async {
    if (_locales.isEmpty) await supportedLocales();
    final id = preferredLocale(locale);
    // Android phones with a downloaded Tamil model can listen offline.
    final onDevice = await _hasOnDevice(id);
    facts['locale'] = id;
    facts['onDevice'] = onDevice;
    await _stt.listen(
      onResult: _onResult,
      onSoundLevelChange: _levels.add,
      listenOptions: SpeechListenOptions(
        localeId: id,
        partialResults: true,
        cancelOnError: false,
        listenMode: ListenMode.dictation,
        onDevice: onDevice,
        pauseFor: pauseFor,
        listenFor: listenFor,
        contextualPhrases: hotwords,
      ),
    );
  }

  void _onResult(SpeechRecognitionResult r) => _results.add(
    VoiceHeard(
      r.recognizedWords,
      alternatives: [for (final a in r.alternates) a.recognizedWords],
      confidence: r.hasConfidenceRating ? r.confidence : null,
      isFinal: r.finalResult,
    ),
  );

  @override
  void changePauseFor(Duration pause) {
    try {
      _stt.changePauseFor(pause);
    } catch (_) {}
  }

  @override
  Future<void> stop() => _stt.stop();
  @override
  Future<void> cancel() => _stt.cancel();

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
    if (_stt.statusListener == _status) _stt.statusListener = null;
    if (_stt.errorListener == _error) _stt.errorListener = null;
    try {
      await _stt.cancel();
    } catch (_) {}
    await _results.close();
    await _levels.close();
    await _errors.close();
    await _statuses.close();
  }
}

/// VIMO's own model, downloaded as an `asr` language pack.
///
/// TODO(offline-asr): the `asr-ta` pack built by tools/voice_training is a
/// tar.bz2 of a fine-tuned Whisper tiny exported to ONNX with int8 weights
/// (encoder, decoder and tokenizer files). Load it with an on-device ONNX
/// runtime (the `onnxruntime` Flutter package, or sherpa-onnx after
/// converting the model to its Whisper layout), feed it 16 kHz mono PCM
/// from the `record` package, and emit [VoiceHeard] results. That needs
/// native libraries in the Android/iOS builds and a real trained model,
/// neither of which can be built and tested in this repository's CI yet.
/// Until then [initialize] throws [UnsupportedError] and
/// [createVoiceEngine] keeps the system engine.
class OfflineSpeechEngine implements VoiceEngine {
  OfflineSpeechEngine(this.modelPath);

  /// The installed pack file (`language_packs/asr-ta/pack.bin`).
  final String modelPath;
  @override
  final Map<String, Object?> facts = {};

  @override
  String get name => 'offline';
  @override
  bool get isOffline => true;
  @override
  bool get isListening => false;

  @override
  Future<bool> initialize() => throw UnsupportedError(
    'VIMO offline voice is not built into this app yet',
  );
  @override
  Future<List<String>> supportedLocales() async => const [];
  @override
  Future<void> start({
    required String locale,
    List<String> hotwords = const [],
    Duration pauseFor = const Duration(seconds: 12),
    Duration listenFor = const Duration(seconds: 55),
  }) => throw UnsupportedError(
    'VIMO offline voice is not built into this app yet',
  );
  @override
  void changePauseFor(Duration pause) {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> cancel() async {}
  @override
  Stream<VoiceHeard> get results => const Stream.empty();
  @override
  Stream<double> get soundLevels => const Stream.empty();
  @override
  Stream<VoiceEngineError> get errors => const Stream.empty();
  @override
  Stream<String> get statuses => const Stream.empty();
  @override
  Future<void> dispose() async {}
}

/// Picks the engine and starts it: VIMO's offline model only when the
/// owner turned on "Use VIMO offline voice (beta)" and its pack is
/// installed; otherwise, or when the offline engine cannot start, the
/// system engine. [log] receives the choice and the reason.
Future<(VoiceEngine, bool)> createVoiceEngine({
  required bool offlineEnabled,
  String? offlineModelPath,
  VoiceEngine Function()? system,
  VoiceEngine Function(String path)? offline,
  void Function(String type, Map<String, Object?> details)? log,
}) async {
  final makeSystem = system ?? SystemSpeechEngine.new;
  if (offlineEnabled && offlineModelPath != null) {
    final engine = (offline ?? OfflineSpeechEngine.new)(offlineModelPath);
    try {
      final ok = await engine.initialize();
      if (ok) {
        log?.call('engine', {'engine': engine.name, 'offline': true});
        return (engine, true);
      }
      log?.call('engine_fallback', {'reason': 'offline engine did not start'});
    } on UnsupportedError catch (e) {
      log?.call('engine_fallback', {'reason': '${e.message}'});
    } catch (e) {
      log?.call('engine_fallback', {'reason': '$e'});
    }
    await engine.dispose();
  } else if (offlineEnabled) {
    log?.call('engine_fallback', {'reason': 'offline pack not installed'});
  }
  final engine = makeSystem();
  final ok = await engine.initialize();
  log?.call('engine', {'engine': engine.name, 'offline': false, 'ok': ok});
  return (engine, ok);
}
