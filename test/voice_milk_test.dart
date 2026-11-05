import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' hide Ink;
import 'package:flutter/services.dart';
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

void main() {
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('vimo_voice_');
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

  test('Tamil phrasing of cow names', () {
    expect(tamilDative('மைனா'), 'மைனாவுக்கு');
    expect(tamilDative('பொன்னி'), 'பொன்னிக்கு');
    expect(tamilDative('ராஜன்'), 'ராஜனுக்கு');
    expect(tamilQuestion('மைனா'), 'மைனாவா');
    expect(tamilQuestion('பொன்னி'), 'பொன்னியா');
  });

  test(
    'voice entries save as milk records with their own time and session',
    () async {
      final morning = DateTime(2026, 11, 5, 6, 12);
      final evening = DateTime(2026, 11, 5, 17, 40);
      final saved = await saveVoiceMilkEntries([
        VoiceMilkEntry(
          id: '1',
          cow: 'Maina',
          litres: 5,
          at: morning,
          heard: 'மைனா 5 லிட்டர்',
        ),
        VoiceMilkEntry(
          id: '2',
          cow: 'Ponni',
          litres: 2.5,
          at: evening,
          heard: '',
        ),
        // Rows without litres are never written.
        VoiceMilkEntry(
          id: '3',
          cow: 'Kutty',
          litres: 0,
          at: evening,
          heard: '',
        ),
      ]);
      expect(saved, 2);
      final rows = Hive.box('milk_records').values.map(asMap).toList();
      expect(rows, hasLength(2));
      expect(rows[0]['cow'], 'Maina');
      expect(rows[0]['quantity'], 5);
      expect(rows[0]['date'], '2026-11-05');
      expect(rows[0]['time'], '06:12');
      expect(rows[0]['session'], 'Morning');
      expect(rows[0]['source'], 'voice');
      expect(rows[1]['session'], 'Evening');
      expect(Hive.box('settings').get('voiceMilkDraft'), isNull);
    },
  );

  testWidgets(
    'a whole milking by voice: wake, add, ask, confirm, finish, save',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final cow in ['Maina', 'Ponni', 'Meena']) {
        await tester.runAsync(
          () => Hive.box('animals').add({
            'type': 'cow',
            'name': cow,
            'status': 'Active',
            'gender': 'Female',
          }),
        );
      }
      final speech = FakeSpeech();
      SpeechToTextPlatform.instance = speech;
      final spoken = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('flutter_tts'),
        (call) async {
          if (call.method == 'speak') spoken.add('${call.arguments}');
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
      Future<void> settle() async {
        for (int i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 250));
          expect(tester.takeException(), isNull);
        }
      }

      Future<void> say(String words) async {
        speech.hear(words);
        await settle();
      }

      await settle();
      expect(speech.locale, 'ta-IN');
      expect(spoken.last, contains('ஹே விமோ'));

      // Talk nearby without the wake word is ignored.
      await say('இன்னைக்கு மழை வருமா');
      expect(spoken.last, contains('ஹே விமோ'));

      await say('ஹே விமோ');
      expect(spoken.last, 'ம்ம்?');

      await say('மைனா 5 லிட்டர் ஆட் பண்ணு');
      expect(spoken.last, contains('5 லிட்டர் சேர்த்தேன்'));

      // "5 இல்லை 6": the entry just added is corrected, not duplicated.
      await say('5 இல்லை 6 லிட்டர்');
      expect(spoken.last, contains('6 லிட்டர் என்று மாற்றினேன்'));

      // Milk sold to a person is never taken as milking.
      await say('செல்விக்கு 2 லிட்டர் பால் விற்றேன்');
      expect(spoken.last, contains('விற்பனை'));

      // A name that only sounds close is confirmed first.
      await say('mena 3 litre');
      expect(spoken.last, 'மீனாவுக்கு 3 லிட்டர். சேர்க்கவா?');
      await say('ஆமா');
      expect(spoken.last, 'மீனாவுக்கு 3 லிட்டர் சேர்த்தேன்.');

      // A missing amount is asked for.
      await say('பொன்னி');
      expect(spoken.last, 'பொன்னிக்கு எத்தனை லிட்டர்?');
      await say('ரெண்டரை');
      expect(spoken.last, 'பொன்னிக்கு 2.5 லிட்டர் சேர்த்தேன்.');

      // A missing cow is asked for.
      await say('4 லிட்டர்');
      expect(spoken.last, '4 லிட்டர். எந்த மாட்டுக்கு?');
      await say('வேண்டாம்');
      expect(spoken.last, contains('விட்டுட்டேன்'));

      await say('பால் கறந்து முடிச்சிட்டேன்');
      expect(spoken.last, contains('மொத்தம் 3 மாட்டுக்கு 11.5 லிட்டர்'));
      expect(find.text('சேமி'), findsOneWidget);
      expect(find.text('11.5 L'), findsWidgets);
      expect(Hive.box('milk_records').isEmpty, isTrue);

      await tester.runAsync(() async {
        await tester.tap(find.text('சேமி'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await settle();
      final rows = Hive.box('milk_records').values.map(asMap).toList();
      expect(rows.map((r) => r['cow']), ['Maina', 'Meena', 'Ponni']);
      expect(rows.map((r) => r['quantity']), [6, 3, 2.5]);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      // Let the recogniser's own pause timer run out.
      await tester.pump(const Duration(seconds: 15));
    },
  );
}
