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
    directory = await Directory.systemTemp.createTemp('vimo_voice_manual_');
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

  Future<void> putDraft(WidgetTester tester, DateTime at) async {
    await tester.runAsync(() async {
      await Hive.box('animals').add({
        'type': 'cow',
        'name': 'Maina',
        'status': 'Active',
        'gender': 'Female',
      });
      await Hive.box('settings').put('voiceMilkDraft', [
        {
          'id': 'a1',
          'cow': 'Maina',
          'litres': 4.0,
          'at': at.toIso8601String(),
          'heard': 'மைனா 4',
        },
        {
          'id': 'a2',
          'cow': 'Maina',
          'litres': 2.0,
          'at': at.toIso8601String(),
          'heard': 'மைனா 2',
        },
      ]);
    });
  }

  testWidgets('typing milk by hand asks about unsaved voice entries first', (
    tester,
  ) async {
    await putDraft(tester, DateTime.now());
    await tester.pumpWidget(
      MaterialApp(
        supportedLocales: const [Locale('en'), Locale('ta')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const AddEntryScreen(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('சேமிக்காத குரல் பதிவுகள்'), findsOneWidget);
    // Only save or delete: there is nothing to review on this screen.
    expect(find.text('பார்த்து திருத்து'), findsNothing);
    await tester.runAsync(() async {
      await tester.tap(find.text('நீக்கு'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await drainHive(tester);
    expect(Hive.box('settings').get('voiceMilkDraft'), isNull);
    expect(Hive.box('milk_records').isEmpty, isTrue);
    await tester.pumpWidget(const SizedBox());
    await drainHive(tester);
  });
}
