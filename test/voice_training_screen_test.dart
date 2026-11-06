import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' hide Ink;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:ranch_management/main.dart';
import 'package:speech_to_text_platform_interface/speech_to_text_platform_interface.dart';


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
    directory = await Directory.systemTemp.createTemp('vimo_voice_train_');
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

  testWidgets('Train VIMO shows the sentence to read and the data promise', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      await Hive.box('animals').add({
        'type': 'cow',
        'name': 'Maina',
        'status': 'Active',
        'gender': 'Female',
      });
      await Hive.openBox('voice_training');
      await Hive.openLazyBox('voice_training_audio');
    });
    await tester.pumpWidget(
      MaterialApp(
        supportedLocales: const [Locale('en'), Locale('ta')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const TrainVimoScreen(),
      ),
    );
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('இந்த வாக்கியத்தைப் படியுங்கள்'), findsOneWidget);
    expect(find.textContaining('மைனா'), findsWidgets);
    expect(find.text('பதிவு செய்'), findsOneWidget);
    await tester.tap(find.text('தரவு'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('training_data'), findsOneWidget);
    await tester.tap(find.text('பயிற்சி'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('GitHub Actions'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
