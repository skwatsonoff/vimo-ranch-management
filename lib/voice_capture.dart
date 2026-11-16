/// One owner for the microphone in VIMO's voice screens, with a real state
/// machine instead of "permission allowed means listening".
///
/// * [VoiceCaptureController.startFromTap] must be called synchronously from
///   the owner's tap: the platform capture (web/vimo_mic.js on the web) opens
///   the microphone and unlocks audio inside that gesture.
/// * Each start gets a new generation. Results, errors and speech replies that
///   belong to an older generation are ignored, so a late transcript, a late
///   Gemini answer or a late permission answer can never act after Stop, an
///   interruption or a restart.
/// * An interruption (audio session interrupted, track muted or ended, page
///   hidden, app paused, route change) stops capture, discards buffered audio
///   and pending transcripts, and waits for an explicit Resume tap. VIMO never
///   restarts the microphone by itself after an interruption.
/// * Microphone, speech-to-text and the spoken reply are separate: a missing
///   Tamil voice or speech service never blocks the microphone or the text
///   reply, and an unavailable speech-to-text service is reported as such.
library;

import 'dart:async';
import 'dart:typed_data';

/// What the screen shows. Only [listening] means VIMO can hear.
enum CapturePhase {
  /// Nothing started yet: the screen offers "Start listening".
  idle,

  /// The microphone is being opened; the browser may be asking.
  connecting,

  /// Safari needs one more tap to start sound after the permission prompt.
  needsTap,

  /// A live microphone delivered real audio: VIMO is listening.
  listening,

  /// A sentence was heard and is being written down.
  processing,

  /// VIMO is speaking its reply (input is gated off meanwhile).
  speaking,

  /// The owner paused, or VIMO is waiting between turns.
  paused,

  /// The platform took the audio away (call, another app, page hidden).
  interrupted,

  /// Something failed: see [VoiceCaptureController.error].
  error,

  /// The owner stopped, or the screen closed.
  stopped,
}

/// Why capture cannot run, with what the screen should offer.
enum CaptureError {
  /// The owner refused the prompt (it can be asked again).
  denied,

  /// The site or app is blocked in settings; only settings can change it.
  blocked,

  /// Another app holds the microphone.
  busy,

  /// The microphone opened but delivered no audio frames.
  noFrames,

  /// The microphone opened but its track stayed muted.
  muted,

  /// No microphone, insecure page, no Web Audio, or a policy block.
  unsupported,

  /// The speech-to-text service is not set up or cannot be reached.
  recognitionUnavailable,

  /// No internet connection for the speech-to-text service.
  offline,

  /// The free speech-to-text quota is used up for now.
  quota,

  /// Starting took too long.
  timeout,

  /// Anything else.
  other,
}

/// Maps a capture failure code from the platform to [CaptureError].
CaptureError captureErrorFromCode(String code) {
  final base = code.split(':').first;
  if (base == 'not-allowed') {
    return code.endsWith(':blocked')
        ? CaptureError.blocked
        : CaptureError.denied;
  }
  return switch (base) {
    'audio-busy' => CaptureError.busy,
    'no-frames' => CaptureError.noFrames,
    'muted' => CaptureError.muted,
    'no-microphone' ||
    'unsupported' ||
    'insecure' ||
    'policy-blocked' ||
    'audio-context' ||
    'no-track' => CaptureError.unsupported,
    'timeout' => CaptureError.timeout,
    _ => CaptureError.other,
  };
}

/// Interruption reasons the platform can report. None of them identifies a
/// phone call: a browser cannot know that. Only a native signal that really
/// names a call sets [CaptureInterruption.isCall].
class CaptureInterruption {
  final String reason;
  final bool isCall;
  const CaptureInterruption(this.reason, {this.isCall = false});
}

/// One finished sentence from the microphone, held only in memory.
class CapturedSpeech {
  final int generation;
  final Uint8List wav;
  final double seconds;
  const CapturedSpeech(this.generation, this.wav, this.seconds);
}

/// Events from the platform capture.
sealed class CaptureEvent {
  final int generation;
  const CaptureEvent(this.generation);
}

class CapturePhaseEvent extends CaptureEvent {
  final String phase;
  final String? reason;
  final String? code;
  const CapturePhaseEvent(
    super.generation,
    this.phase, {
    this.reason,
    this.code,
  });
}

class CaptureLevelEvent extends CaptureEvent {
  final double level;
  const CaptureLevelEvent(super.generation, this.level);
}

class CaptureSpeechEvent extends CaptureEvent {
  final CapturedSpeech speech;
  CaptureSpeechEvent(this.speech) : super(speech.generation);
}

class CaptureDiagEvent extends CaptureEvent {
  final Map<String, Object?> details;
  const CaptureDiagEvent(super.generation, this.details);
}

/// The platform capture: web/vimo_mic.js on the web, a fake in tests.
abstract class CaptureBackend {
  /// Whether capture can run here at all.
  bool get supported;

  /// Opens the microphone for [generation]. Must start its work
  /// synchronously (inside the tap). Completes with 'ready', or throws a
  /// [CaptureFailure] with the platform's code.
  Future<void> start(int generation);

  /// The extra tap Safari may need after the permission prompt.
  Future<void> resumeAudio(int generation);

  /// Drops input while VIMO speaks.
  void gate(int generation, bool on);

  /// Releases the microphone and every buffer.
  void stop(int generation, String reason);

  Stream<CaptureEvent> get events;
}

class CaptureFailure implements Exception {
  final String code;
  const CaptureFailure(this.code);
  @override
  String toString() => 'CaptureFailure($code)';
}

/// Speech-to-text for one sentence.
abstract class SpeechToTextService {
  /// Short name for the diagnostics log and the status panel.
  String get name;

  /// Whether the service is set up (it may still fail when called).
  bool get configured;

  /// Writes down [wav]. Returns null when nothing was understood. Throws
  /// [SpeechServiceFailure] when the service cannot help.
  Future<String?> transcribe(
    Uint8List wav, {
    required String locale,
    List<String> hints = const [],
  });
}

class SpeechServiceFailure implements Exception {
  final CaptureError error;
  const SpeechServiceFailure(this.error);
  @override
  String toString() => 'SpeechServiceFailure(${error.name})';
}

/// No speech-to-text service is set up: say so instead of pretending.
class UnavailableSpeechToText implements SpeechToTextService {
  const UnavailableSpeechToText();
  @override
  String get name => 'none';
  @override
  bool get configured => false;
  @override
  Future<String?> transcribe(
    Uint8List wav, {
    required String locale,
    List<String> hints = const [],
  }) async =>
      throw const SpeechServiceFailure(CaptureError.recognitionUnavailable);
}

/// Owns the microphone for one voice screen.
class VoiceCaptureController {
  VoiceCaptureController({
    required this.backend,
    required this.speechToText,
    required this.locale,
    this.hints = const [],
    this.log,
    this.startTimeout = const Duration(seconds: 45),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    _sub = backend.events.listen(_onEvent);
  }

  final CaptureBackend backend;
  SpeechToTextService speechToText;
  String locale;
  List<String> hints;

  /// Redacted diagnostics: phases, codes and timings, never audio or text.
  final void Function(String type, Map<String, Object?> details)? log;

  /// How long the whole start (including an open permission prompt) may
  /// take before the screen offers to try again.
  final Duration startTimeout;
  final DateTime Function() _clock;
  late final StreamSubscription<CaptureEvent> _sub;

  final _phases = StreamController<CapturePhase>.broadcast();
  final _transcripts = StreamController<String>.broadcast();
  final _levels = StreamController<double>.broadcast();

  int _generation = 0;
  CapturePhase _phase = CapturePhase.idle;
  CaptureError? _error;
  CaptureInterruption? _interruption;
  Timer? _watchdog;
  DateTime? _tapAt;
  bool _disposed = false;
  int _inFlight = 0;

  int get generation => _generation;
  CapturePhase get phase => _phase;
  CaptureError? get error => _error;
  CaptureInterruption? get interruption => _interruption;

  /// The microphone is open for this session (listening, thinking or
  /// speaking between turns).
  bool get open => const {
    CapturePhase.listening,
    CapturePhase.processing,
    CapturePhase.speaking,
    CapturePhase.paused,
  }.contains(_phase);

  Stream<CapturePhase> get phases => _phases.stream;

  /// Each sentence written down, for the current generation only.
  Stream<String> get transcripts => _transcripts.stream;
  Stream<double> get levels => _levels.stream;

  /// Whether [generation] is still the live session.
  bool isCurrent(int generation) =>
      !_disposed && generation == _generation && open;

  void _set(CapturePhase next, {CaptureError? error}) {
    if (_disposed) return;
    _error = error;
    if (next == _phase && error == null) return;
    _phase = next;
    _log('capture_phase', {
      'phase': next.name,
      if (error != null) 'error': error.name,
      if (_interruption != null && next == CapturePhase.interrupted)
        'reason': _interruption!.reason,
    });
    _phases.add(next);
  }

  void _log(String type, Map<String, Object?> details) {
    try {
      log?.call(type, {
        'gen': _generation,
        if (_tapAt != null)
          'msSinceTap': _clock().difference(_tapAt!).inMilliseconds,
        ...details,
      });
    } catch (_) {}
  }

  /// Call synchronously from the owner's tap ("Start listening" or "Resume
  /// listening"). Returns the new generation.
  int startFromTap() {
    if (_disposed) return _generation;
    if (_phase == CapturePhase.needsTap) {
      final generation = _generation;
      _tapAt = _clock();
      _set(CapturePhase.connecting);
      unawaited(_await(backend.resumeAudio(generation), generation));
      return generation;
    }
    if (!backend.supported) {
      _set(CapturePhase.error, error: CaptureError.unsupported);
      return _generation;
    }
    if (!speechToText.configured) {
      // No point opening the microphone when nothing can write it down.
      _set(CapturePhase.error, error: CaptureError.recognitionUnavailable);
      return _generation;
    }
    final generation = ++_generation;
    _interruption = null;
    _tapAt = _clock();
    _set(CapturePhase.connecting);
    // Synchronous: the platform opens the microphone inside this gesture.
    final started = backend.start(generation);
    unawaited(_await(started, generation));
    return generation;
  }

  Future<void> _await(Future<void> started, int generation) async {
    _watchdog?.cancel();
    _watchdog = Timer(startTimeout, () {
      if (generation != _generation || _phase != CapturePhase.connecting) {
        return;
      }
      backend.stop(generation, 'timeout');
      _set(CapturePhase.error, error: CaptureError.timeout);
    });
    try {
      await started;
      if (generation != _generation || _phase != CapturePhase.connecting) {
        return;
      }
      _watchdog?.cancel();
      _log('capture_ready', const {});
      _set(CapturePhase.listening);
    } on CaptureFailure catch (failure) {
      if (generation != _generation) return;
      _watchdog?.cancel();
      if (failure.code == 'cancelled' || failure.code == 'stale-generation') {
        return;
      }
      if (failure.code == 'needs-gesture') {
        _set(CapturePhase.needsTap);
        return;
      }
      if (failure.code == 'interruption-active' ||
          failure.code == 'interrupted') {
        _interruption ??= const CaptureInterruption('active');
        _set(CapturePhase.interrupted);
        return;
      }
      _set(CapturePhase.error, error: captureErrorFromCode(failure.code));
    } catch (error) {
      if (generation != _generation) return;
      _watchdog?.cancel();
      _set(CapturePhase.error, error: CaptureError.other);
    }
  }

  void _onEvent(CaptureEvent event) {
    if (_disposed || event.generation != _generation) return;
    switch (event) {
      case CapturePhaseEvent(phase: 'interrupted', :final reason):
        interrupt(
          CaptureInterruption(reason ?? 'platform'),
          fromPlatform: true,
        );
      case CapturePhaseEvent(phase: 'error', :final code)
          when _phase != CapturePhase.connecting &&
              _phase != CapturePhase.error:
        _set(CapturePhase.error, error: captureErrorFromCode(code ?? 'other'));
      case CapturePhaseEvent():
        break;
      case CaptureLevelEvent(:final level):
        if (_phase == CapturePhase.listening) _levels.add(level);
      case CaptureSpeechEvent(:final speech):
        unawaited(_transcribe(speech));
      case CaptureDiagEvent(:final details):
        _log('capture_diag', details);
    }
  }

  Future<void> _transcribe(CapturedSpeech speech) async {
    final generation = speech.generation;
    if (!isCurrent(generation) ||
        (_phase != CapturePhase.listening &&
            _phase != CapturePhase.processing)) {
      return;
    }
    _inFlight++;
    _set(CapturePhase.processing);
    final started = _clock();
    try {
      final text = await speechToText.transcribe(
        speech.wav,
        locale: locale,
        hints: hints,
      );
      // A late answer for an older session never reaches the dialogue.
      if (!isCurrent(generation)) {
        _log('asr_late_dropped', const {});
        return;
      }
      _log('asr_done', {
        'service': speechToText.name,
        'ms': _clock().difference(started).inMilliseconds,
        'seconds': speech.seconds,
        'empty': text == null || text.trim().isEmpty,
      });
      if (_phase == CapturePhase.processing && _inFlight <= 1) {
        _set(CapturePhase.listening);
      }
      if (text != null && text.trim().isNotEmpty) _transcripts.add(text.trim());
    } on SpeechServiceFailure catch (failure) {
      if (!isCurrent(generation)) return;
      backend.stop(generation, 'asr-${failure.error.name}');
      _generation++;
      _set(CapturePhase.error, error: failure.error);
    } catch (_) {
      if (!isCurrent(generation)) return;
      if (_phase == CapturePhase.processing) _set(CapturePhase.listening);
    } finally {
      _inFlight--;
    }
  }

  /// Number of sentences still being written down (for tests).
  int get inFlight => _inFlight;

  /// VIMO is about to speak: input off, half-heard speech dropped.
  void beginSpeaking() {
    if (!open) return;
    backend.gate(_generation, true);
    _set(CapturePhase.speaking);
  }

  /// VIMO finished speaking: listen again, only if the session is still
  /// the same, live, foreground one.
  void endSpeaking() {
    if (_phase != CapturePhase.speaking && _phase != CapturePhase.paused) {
      return;
    }
    backend.gate(_generation, false);
    _set(CapturePhase.listening);
  }

  /// Pause between turns without closing the microphone.
  void pause() {
    if (!open) return;
    backend.gate(_generation, true);
    _set(CapturePhase.paused);
  }

  /// The platform (or the app lifecycle) took the audio away. Everything
  /// in flight is dropped; only a new tap starts again.
  void interrupt(CaptureInterruption why, {bool fromPlatform = false}) {
    if (_disposed) return;
    if (_phase == CapturePhase.idle ||
        _phase == CapturePhase.stopped ||
        _phase == CapturePhase.interrupted) {
      return;
    }
    final old = _generation;
    if (!fromPlatform) backend.stop(old, 'interrupt-${why.reason}');
    _generation++;
    _watchdog?.cancel();
    _interruption = why;
    _set(CapturePhase.interrupted);
  }

  /// Stop, navigation, sign-out or session timeout.
  void stop([String reason = 'stop']) {
    if (_disposed) return;
    backend.stop(_generation, reason);
    _generation++;
    _watchdog?.cancel();
    if (_phase != CapturePhase.idle) _set(CapturePhase.stopped);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    stop('dispose');
    _disposed = true;
    _watchdog?.cancel();
    await _sub.cancel();
    await _phases.close();
    await _transcripts.close();
    await _levels.close();
  }
}

/// A test backend: records calls and lets tests drive events.
class FakeCaptureBackend implements CaptureBackend {
  FakeCaptureBackend({this.supported = true});

  @override
  final bool supported;
  final _events = StreamController<CaptureEvent>.broadcast(sync: true);
  final List<String> calls = [];
  Completer<void>? pendingStart;
  bool gated = false;
  int? openGeneration;

  @override
  Stream<CaptureEvent> get events => _events.stream;

  @override
  Future<void> start(int generation) {
    calls.add('start:$generation');
    openGeneration = generation;
    pendingStart = Completer<void>();
    return pendingStart!.future;
  }

  @override
  Future<void> resumeAudio(int generation) {
    calls.add('resumeAudio:$generation');
    pendingStart = Completer<void>();
    return pendingStart!.future;
  }

  @override
  void gate(int generation, bool on) {
    calls.add('gate:$generation:$on');
    if (generation == openGeneration) gated = on;
  }

  @override
  void stop(int generation, String reason) {
    calls.add('stop:$generation:$reason');
    if (generation == openGeneration) openGeneration = null;
  }

  void ready() => pendingStart?.complete();
  void fail(String code) => pendingStart?.completeError(CaptureFailure(code));
  void emit(CaptureEvent event) => _events.add(event);

  /// A sentence of fake audio for [generation].
  void speak(int generation, [double seconds = 1.2]) => emit(
    CaptureSpeechEvent(
      CapturedSpeech(
        generation,
        Uint8List.fromList(List.filled(44, 0)),
        seconds,
      ),
    ),
  );
}
