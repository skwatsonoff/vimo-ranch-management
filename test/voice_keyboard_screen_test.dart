import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' hide Ink;
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:ranch_management/main.dart';
import 'package:ranch_management/mic_permission.dart';
import 'package:speech_to_text_platform_interface/speech_to_text_platform_interface.dart';

import 'fake_mic_backend.dart';

/// The phone's recogniser, scripted: [hear] delivers one spoken sentence.
class FakeSpeech extends SpeechToTextPlatform {
  int listens = 0;
  String? locale;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<bool> initialize({
    debugLogging = false,
    List<SpeechConfigOption>? options,
  }) async => true;

  @override
  Future<bool> listen({
    String? localeId,
    partialResults = true,
    onDevice = false,
    int listenMode = 0,
    sampleRate = 0,
    SpeechListenOptions? options,
  }) async {
    listens++;
    locale = localeId;
    onStatus?.call('listening');
    return true;
  }

  @override
  Future<void> stop() async => onStatus?.call('done');

  @override
  Future<void> cancel() async {}

  @override
  Future<List<dynamic>> locales() async => [];

  void fail(String code) {
    onError?.call(jsonEncode({'errorMsg': code, 'permanent': true}));
    onStatus?.call('done');
  }

  void hear(String words) {
    onTextRecognition?.call(
      jsonEncode({
        'alternates': [
          {'recognizedWords': words, 'confidence': .9},
        ],
        'resultType': 2,
      }),
    );
    onStatus?.call('done');
  }
}

/// One recogniser for every test, as in the app: the speech plugin binds
/// its callbacks to the platform only on its first start.
final sharedSpeech = FakeSpeech();

/// Lets Hive writes started under the test's fake clock finish, so the next
/// test's set-up is not left waiting on them.
Future<void> drainHive(WidgetTester tester) async {
  for (int i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump();
  }
}

void main() {
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('vimo_voice_keyboard_');
    Hive.init(directory.path);
    for (final name in backupBoxNames) {
      await Hive.openBox(name);
    }
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
  });
  tearDownAll(() async {
    AutoSyncService.stop();
    // Draft writes started inside the widget test's fake clock never finish;
    // they hold Hive's write queue, so closing must not wait on them.
    await Future.any<void>([
      Hive.close(),
      Future<void>.delayed(const Duration(seconds: 3)),
    ]);
    try {
      await directory.delete(recursive: true);
    } catch (_) {}
  });

  Future<FakeSpeech> openVoice(
    WidgetTester tester,
    FakeMicBackend mic, {
    List<String>? spoken,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(
      () => Hive.box('animals').add({
        'type': 'cow',
        'name': 'Maina',
        'status': 'Active',
        'gender': 'Female',
      }),
    );
    final speech = sharedSpeech..listens = 0;
    SpeechToTextPlatform.instance = speech;
    MicPermission.backend = mic;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('flutter_tts'),
      (call) async {
        if (call.method == 'speak') spoken?.add('${call.arguments}');
        return 1;
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        supportedLocales: const [Locale('en'), Locale('ta')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const VoiceMilkScreen(),
      ),
    );
    for (int i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    return speech;
  }

  Future<void> closeVoice(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 15));
    await drainHive(tester);
  }

  testWidgets('iPhone Home Screen app listens through keyboard dictation', (
    tester,
  ) async {
    debugKeyboardDictation = true;
    addTearDown(() => debugKeyboardDictation = false);
    final speech = await openVoice(
      tester,
      FakeMicBackend(statuses: [MicAccess.denied]),
    );
    // No error card and no browser speech service: the 🎤 box instead.
    final box = find.byKey(const ValueKey('voice-dictation-box'));
    expect(box, findsOneWidget);
    expect(find.text('கையால் பதிவு செய்'), findsNothing);
    expect(speech.listens, 0);
    await tester.tap(box);
    await tester.pump();
    await tester.enterText(box, 'மைனா 5 லிட்டர்');
    for (int i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    await tester.enterText(box, 'மைனா 5 லிட்டர் மைனா 3 லிட்டர்');
    for (int i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    // Maina already has 5 L: VIMO asks, and the answer comes the same way.
    expect(find.textContaining('இன்னும் 3 லிட்டர் சேர்க்கவா'), findsOneWidget);
    await tester.enterText(box, 'மைனா 5 லிட்டர் மைனா 3 லிட்டர் ஆமா');
    for (int i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    await drainHive(tester);
    final draft = (Hive.box('settings').get('voiceMilkDraft') as List)
        .map((e) => (e as Map)['litres'])
        .toList();
    expect(draft, [5.0, 3.0]);
    await closeVoice(tester);
  });
}
