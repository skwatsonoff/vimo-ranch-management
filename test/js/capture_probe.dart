// Compiled to JS by test/js/capture_interop_test.cjs: drives the real
// WebCaptureBackend + VoiceCaptureController against web/vimo_mic.js.
import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:ranch_management/voice_capture.dart';
import 'package:ranch_management/voice_capture_web.dart';

@JS('probeLog')
external void probeLog(String line);

class EchoAsr implements SpeechToTextService {
  int calls = 0;
  int lastBytes = 0;
  @override
  String get name => 'echo';
  @override
  bool get configured => true;
  @override
  Future<String?> transcribe(
    Uint8List wav, {
    required String locale,
    List<String> hints = const [],
  }) async {
    calls++;
    lastBytes = wav.length;
    final riff = String.fromCharCodes(wav.sublist(0, 4));
    return 'heard $riff ${wav.length}';
  }
}

@JS('probeStart')
external set _probeStart(JSFunction f);
@JS('probeInterrupt')
external set _probeInterrupt(JSFunction f);

late VoiceCaptureController controller;

void main() {
  final backend = webCaptureBackend()!;
  final asr = EchoAsr();
  controller = VoiceCaptureController(
    backend: backend,
    speechToText: asr,
    locale: 'ta-IN',
  );
  controller.phases.listen(
    (p) => probeLog(
      'phase:${p.name}${controller.error != null ? ':${controller.error!.name}' : ''}${controller.interruption != null && p == CapturePhase.interrupted ? ':${controller.interruption!.reason}' : ''}',
    ),
  );
  controller.transcripts.listen((t) => probeLog('text:$t'));
  _probeStart = (() {
    probeLog('gen:${controller.startFromTap()}');
  }).toJS;
  _probeInterrupt = (() {
    controller.interrupt(const CaptureInterruption('lifecycle-paused'));
  }).toJS;
  probeLog('supported:${backend.supported}');
}
