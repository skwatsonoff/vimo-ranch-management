// The real voice milk screen on the capture path (iPhone web), driven by a
// fake microphone and a fake speech-to-text service.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart' hide Ink;
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:ranch_management/main.dart';
import 'package:ranch_management/voice_capture.dart';

class ScriptedAsr implements SpeechToTextService {
  bool ready = true;
  final List<Completer<String?>> calls = [];
  @override
  String get name => 'scripted';
  @override
  bool get configured => ready;
  @override
  Future<String?> transcribe(Uint8List wav, {required String locale, List<String> hints = const []}) {
    final c = Completer<String?>();
    calls.add(c);
    return c.future;
  }
}

void main() {
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('vimo_capture_');
    Hive.init(directory.path);
    for (final name in backupBoxNames) {
      await Hive.openBox(name);
    }
  });
  tearDownAll(() async {
    debugVoiceCapture = false;
    debugCaptureBackend = null;
    debugSpeechToText = null;
    await Future.any<void>([Hive.close(), Future<void>.delayed(const Duration(seconds: 3))]);
    try {
      await directory.delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    AutoSyncService.stop();
    for (final name in backupBoxNames) {
      await Hive.box(name).clear();
    }
    await Hive.box('settings').putAll({
      'currentRole': 'Admin',
      'currentUser': 'Tester',
      'languageMode': 'Tamil',
      'workspaceSyncEnabled': false,
    });
    for (final cow in ['Kanmani', 'Lakshmi']) {
      await Hive.box('animals').add({'type': 'cow', 'name': cow, 'status': 'Active', 'gender': 'Female'});
    }
  });

  late FakeCaptureBackend mic;
  late ScriptedAsr asr;
  late List<String> spoken;
  Future<void> hear(WidgetTester tester, String words) => hearWith(tester, mic, asr, words);

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    mic = FakeCaptureBackend();
    asr = ScriptedAsr();
    debugVoiceCapture = true;
    debugCaptureBackend = () => mic;
    debugSpeechToText = asr;
    spoken = [];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('flutter_tts'),
      (call) async {
        if (call.method == 'speak') spoken.add('${call.arguments}');
        return 1;
      },
    );
    await tester.pumpWidget(MaterialApp(
      supportedLocales: const [Locale('en'), Locale('ta')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const VoiceMilkScreen(),
    ));
    await settle(tester);
  }

  final scenarios = <String, Future<void> Function(WidgetTester)>{};

  scenarios['no mic until the tap; listening only after real audio; a sentence is understood'] = (tester) async {
    await open(tester);
    expect(find.text('கேட்கத் தொடங்கு'), findsOneWidget);
    expect(find.text('கையால் பதிவு'), findsOneWidget, reason: 'Manual Entry is always there');
    expect(mic.calls, isEmpty, reason: 'opening the screen must not touch the microphone');

    await tapAction(tester);
    await tester.pump();
    expect(mic.calls, ['start:1']);
    expect(find.textContaining('மைக்குடன் இணைகிறது'), findsOneWidget, reason: 'permission/connecting, not "listening"');
    expect(spoken, isEmpty);

    mic.ready();
    await settle(tester);
    expect(spoken.last, contains('ஹே விமோ'));

    await hear(tester, 'ஹே விமோ');
    expect(spoken.last, 'ம்ம்?');
    await hear(tester, 'கண்மணி அஞ்சு லிட்டர்');
    expect(spoken.last, contains('5 லிட்டர் சேர்த்தேன்'));
    expect(mic.calls.where((c) => c.startsWith('gate:1:true')), isNotEmpty, reason: 'input gated while VIMO speaks');
    await close(tester);
  };

  scenarios['interruption: paused card, late transcript dropped, explicit resume'] = (tester) async {
    await open(tester);
    await tapAction(tester);
    await tester.pump();
    mic.ready();
    await settle(tester);
    await hear(tester, 'ஹே விமோ');
    mic.speak(1);
    await tester.pump();
    mic.emit(const CapturePhaseEvent(1, 'interrupted', reason: 'audio-session-interrupted'));
    await settle(tester);
    expect(find.textContaining('குரல் பதிவு இடைநிறுத்தப்பட்டது'), findsWidgets);
    expect(find.textContaining('அழைப்பில்'), findsNothing, reason: 'web cannot know it was a call');
    final before = spoken.length;
    asr.calls.last.complete('கண்மணி அஞ்சு லிட்டர்');
    await settle(tester);
    expect(spoken.length, before, reason: 'late result after interruption does nothing');
    expect(find.textContaining('சேர்த்தேன்'), findsNothing);
    final starts = mic.calls.where((c) => c.startsWith('start:')).length;
    await settle(tester);
    expect(mic.calls.where((c) => c.startsWith('start:')).length, starts, reason: 'no automatic restart');

    expect(find.text('மீண்டும் கேள்'), findsOneWidget);
    await tapAction(tester);
    await tester.pump();
    expect(mic.calls.last, startsWith('start:'));
    mic.ready();
    await settle(tester);
    expect(spoken.last, 'கேட்கிறேன்.');
    await close(tester);
  };

  scenarios['allowed but no audio frames: actionable message, never "listening"'] = (tester) async {
    await open(tester);
    await tapAction(tester);
    await tester.pump();
    mic.fail('no-frames');
    await settle(tester);
    expect(find.text('மைக்கிலிருந்து ஒலி வரவில்லை'), findsOneWidget);
    expect(find.text('மீண்டும் முயற்சி'), findsOneWidget);
    expect(spoken, isEmpty);
    await close(tester);
  };

  scenarios['Safari extra tap: one more tap resumes the same capture'] = (tester) async {
    await open(tester);
    await tapAction(tester);
    await tester.pump();
    mic.fail('needs-gesture');
    await settle(tester);
    expect(find.text('கேட்கத் தொடங்கத் தட்டுங்கள்'), findsOneWidget);
    await tapAction(tester);
    await tester.pump();
    expect(mic.calls.last, 'resumeAudio:1');
    mic.ready();
    await settle(tester);
    expect(spoken, isNotEmpty);
    await close(tester);
  };

  scenarios['no speech service: unavailable state, Manual Entry, mic never opened'] = (tester) async {
    await open(tester);
    asr.ready = false;
    // Re-open with the service unavailable.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(MaterialApp(
      supportedLocales: const [Locale('en'), Locale('ta')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const VoiceMilkScreen(),
    ));
    await settle(tester);
    expect(find.text('குரல் அறிதல் இன்னும் அமைக்கப்படவில்லை'), findsOneWidget);
    expect(find.byKey(const ValueKey('capture-action')), findsNothing);
    expect(find.text('கையால் பதிவு'), findsOneWidget);
    expect(mic.calls.where((c) => c.startsWith('start')), isEmpty);
    await close(tester);
  };

  scenarios['leaving the screen releases the microphone'] = (tester) async {
    await open(tester);
    await tapAction(tester);
    await tester.pump();
    mic.ready();
    await settle(tester);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
    expect(mic.calls.any((c) => c.startsWith('stop:') && c.contains('navigation')), isTrue);
    await close(tester);
  };

  testWidgets('capture path on the real voice screen', (tester) async {
    for (final entry in scenarios.entries) {
      await entry.value(tester);
    }
  });
}

/// One sentence heard: the fake mic delivers audio, the fake service
/// writes it down.
Future<void> hearWith(WidgetTester tester, FakeCaptureBackend mic, ScriptedAsr asr, String words) async {
  final gen = mic.openGeneration ?? 1;
  mic.speak(gen);
  await tester.pump();
  asr.calls.last.complete(words);
  await settle(tester);
}

Future<void> tapAction(WidgetTester tester) async {
  final button = find.byKey(const ValueKey('capture-action'));
  await tester.ensureVisible(button);
  await tester.pump();
  await tester.tap(button);
}

/// Closes the screen and lets Hive writes from the fake clock finish.
Future<void> close(WidgetTester tester) async {
  await drain(tester);
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 30));
  await drain(tester);
}

Future<void> drain(WidgetTester tester) async {
  for (int i = 0; i < 20; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
    await tester.pump();
  }
}

Future<void> settle(WidgetTester tester) async {
  for (int i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

