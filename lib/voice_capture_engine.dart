/// [VoiceEngine] on top of [VoiceCaptureController], so the existing milk
/// dialogue (lib/voice_milk.dart) can use the new capture path unchanged.
///
/// The dialogue restarts its engine from timers (after VIMO speaks, after a
/// silence). Here a restart never opens the microphone: it only lets input
/// through again when the same foreground session is still open. Opening
/// the microphone happens only in [VoiceCaptureController.startFromTap].
library;

import 'dart:async';

import 'voice_capture.dart';
import 'voice_engine.dart';

/// Error codes this engine reports to the dialogue.
abstract final class CaptureEngineCodes {
  /// Waiting for the owner's tap (start, resume, or Safari's extra tap).
  static const needsTap = 'capture-needs-tap';
  static const interrupted = 'capture-interrupted';
  static const prefix = 'capture-';
}

class CaptureVoiceEngine implements VoiceEngine {
  CaptureVoiceEngine(this.controller) {
    _subs.add(
      controller.transcripts.listen((text) {
        if (!_closed) _results.add(VoiceHeard(text, isFinal: true));
      }),
    );
    _subs.add(
      controller.levels.listen((l) {
        if (!_closed) _levels.add(l);
      }),
    );
    _subs.add(controller.phases.listen(_onPhase));
  }

  final VoiceCaptureController controller;
  final _results = StreamController<VoiceHeard>.broadcast();
  final _levels = StreamController<double>.broadcast();
  final _errors = StreamController<VoiceEngineError>.broadcast();
  final _statuses = StreamController<String>.broadcast();
  final List<StreamSubscription<Object?>> _subs = [];
  bool _closed = false;

  @override
  final Map<String, Object?> facts = {'engine': 'vimo-capture'};

  @override
  String get name => 'vimo-capture';
  @override
  bool get isOffline => false;
  @override
  bool get isListening =>
      controller.phase == CapturePhase.listening ||
      controller.phase == CapturePhase.processing;

  void _onPhase(CapturePhase phase) {
    if (_closed) return;
    switch (phase) {
      case CapturePhase.listening:
        _statuses.add(VoiceStatus.listening);
      case CapturePhase.interrupted:
        _statuses.add(VoiceStatus.notListening);
        _errors.add(
          const VoiceEngineError(
            CaptureEngineCodes.interrupted,
            permanent: true,
          ),
        );
      case CapturePhase.error:
        _statuses.add(VoiceStatus.notListening);
        _errors.add(
          VoiceEngineError(
            '${CaptureEngineCodes.prefix}${controller.error?.name ?? 'other'}',
            permanent: true,
          ),
        );
      case CapturePhase.needsTap:
        _errors.add(
          const VoiceEngineError(CaptureEngineCodes.needsTap, permanent: true),
        );
      case CapturePhase.processing:
      case CapturePhase.connecting:
        break;
      case CapturePhase.idle:
      case CapturePhase.speaking:
      case CapturePhase.paused:
      case CapturePhase.stopped:
        _statuses.add(VoiceStatus.notListening);
    }
  }

  @override
  Future<bool> initialize() async =>
      controller.backend.supported && controller.speechToText.configured;

  @override
  Future<List<String>> supportedLocales() async => const [];

  @override
  Future<void> start({
    required String locale,
    List<String> hotwords = const [],
    Duration pauseFor = const Duration(seconds: 12),
    Duration listenFor = const Duration(seconds: 55),
  }) async {
    if (_closed) return;
    controller.locale = locale;
    controller.hints = hotwords;
    switch (controller.phase) {
      case CapturePhase.speaking:
      case CapturePhase.paused:
        controller.endSpeaking();
      case CapturePhase.listening:
      case CapturePhase.processing:
      case CapturePhase.connecting:
        break;
      default:
        // Never opens the microphone from a timer: the owner must tap.
        _errors.add(
          const VoiceEngineError(CaptureEngineCodes.needsTap, permanent: true),
        );
    }
  }

  @override
  void changePauseFor(Duration pause) {}

  /// The dialogue stops listening while VIMO speaks or thinks: gate input.
  @override
  Future<void> stop() async => controller.pause();
  @override
  Future<void> cancel() async => controller.pause();

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
    if (_closed) return;
    _closed = true;
    for (final s in _subs) {
      await s.cancel();
    }
    await controller.dispose();
    await _results.close();
    await _levels.close();
    await _errors.close();
    await _statuses.close();
  }
}
