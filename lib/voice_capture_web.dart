// Dart side of web/vimo_mic.js.
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'voice_capture.dart';

@JS('vimoMic')
external _Mic? get _mic;

@JS('vimoLegacyModels')
external _Legacy? get _legacy;

extension type _Mic(JSObject _) implements JSObject {
  external JSPromise<JSString> start(
    int generation,
    JSFunction onEvent,
    JSFunction onSegment,
  );
  external JSPromise<JSString> resumeAudio(int generation);
  external void gate(int generation, bool on);
  external void stop(int generation, String reason);
  external String capabilities();
}

extension type _Legacy(JSObject _) implements JSObject {
  external JSPromise<JSString> list();
  external JSPromise<JSNumber> remove();
}

CaptureBackend? webCaptureBackend() => _mic == null ? null : WebCaptureBackend();

class WebCaptureBackend implements CaptureBackend {
  final _events = StreamController<CaptureEvent>.broadcast(sync: true);

  @override
  bool get supported {
    try {
      final caps = jsonDecode(_mic!.capabilities()) as Map<String, dynamic>;
      return caps['mediaDevices'] == true && caps['audioContext'] == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Stream<CaptureEvent> get events => _events.stream;

  void _onEvent(JSString raw) {
    try {
      final m = jsonDecode(raw.toDart) as Map<String, dynamic>;
      final gen = (m['gen'] as num?)?.toInt() ?? -1;
      switch (m['type']) {
        case 'phase':
          _events.add(
            CapturePhaseEvent(
              gen,
              '${m['phase']}',
              reason: m['reason'] as String?,
              code: m['code'] as String?,
            ),
          );
        case 'level':
          _events.add(CaptureLevelEvent(gen, (m['level'] as num).toDouble()));
        case 'diag':
          // Only steps, flags and error names: never audio or words.
          _events.add(CaptureDiagEvent(gen, {
            for (final e in m.entries)
              if (e.key != 'type' && e.key != 'gen') e.key: e.value,
          }));
      }
    } catch (_) {}
  }

  void _onSegment(JSNumber gen, JSUint8Array wav, JSNumber seconds) {
    _events.add(
      CaptureSpeechEvent(
        CapturedSpeech(gen.toDartInt, wav.toDart, seconds.toDartDouble),
      ),
    );
  }

  Future<void> _wrap(JSPromise<JSString> promise) async {
    try {
      await promise.toDart;
    } catch (error) {
      throw CaptureFailure(_code(error));
    }
  }

  static String _code(Object error) {
    final text = '$error';
    final match = RegExp(
      r'(not-allowed(?::blocked)?|audio-busy|no-microphone|audio-capture|no-frames|muted|unsupported|insecure|policy-blocked|audio-context|no-track|needs-gesture|interruption-active|cancelled|stale-generation|audio-suspended|error)',
    ).firstMatch(text);
    return match?.group(1) ?? 'audio-capture';
  }

  @override
  Future<void> start(int generation) {
    final mic = _mic;
    if (mic == null) return Future.error(const CaptureFailure('unsupported'));
    // Called synchronously from the tap: the JS opens the mic right here.
    final promise = mic.start(generation, _onEvent.toJS, _onSegment.toJS);
    return _wrap(promise);
  }

  @override
  Future<void> resumeAudio(int generation) {
    final mic = _mic;
    if (mic == null) return Future.error(const CaptureFailure('unsupported'));
    return _wrap(mic.resumeAudio(generation));
  }

  @override
  void gate(int generation, bool on) {
    try {
      _mic?.gate(generation, on);
    } catch (_) {}
  }

  @override
  void stop(int generation, String reason) {
    try {
      _mic?.stop(generation, reason);
    } catch (_) {}
  }
}

Future<List<String>> legacyEarCaches() async {
  try {
    final raw = await _legacy!.list().toDart;
    return [for (final n in jsonDecode(raw.toDart) as List) '$n'];
  } catch (_) {
    return const [];
  }
}

Future<int> removeLegacyEarCaches() async {
  try {
    return (await _legacy!.remove().toDart).toDartInt;
  } catch (_) {
    return 0;
  }
}
