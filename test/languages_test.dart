import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:ranch_management/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('vimo_lang_');
    Hive.init(dir.path);
    await Hive.openBox('settings');
  });
  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('Every language file covers the same messages with intact values', () {
    final codes = [
      for (final l in appLanguages)
        if (l.code != 'en' && l.code != 'ta') l.code,
    ];
    final placeholder = RegExp(r'\{\d+\}');
    Set<String> slots(String s) =>
        placeholder.allMatches(s).map((m) => m.group(0)!).toSet();
    Set<String>? keys;
    for (final code in codes) {
      final file = File('assets/l10n/$code.json');
      expect(file.existsSync(), isTrue, reason: '$code.json missing');
      final map = Map<String, String>.from(
        jsonDecode(file.readAsStringSync()) as Map,
      );
      keys ??= map.keys.toSet();
      expect(map.keys.toSet(), keys, reason: '$code has different messages');
      for (final e in map.entries) {
        expect(e.value.trim(), isNotEmpty, reason: '$code: ${e.key}');
        expect(slots(e.value), slots(e.key), reason: '$code: ${e.key}');
      }
    }
  });

  test('English and Tamil come from the code; others from their file', () async {
    await Hive.box('settings').put('languageMode', 'English');
    expect(bi('Milk', 'பால்'), 'Milk');
    await Hive.box('settings').put('languageMode', 'Tamil');
    expect(bi('Milk', 'பால்'), 'பால்');

    await loadAppLanguage('Hindi');
    await Hive.box('settings').put('languageMode', 'Hindi');
    final hindi = Map<String, String>.from(
      jsonDecode(File('assets/l10n/hi.json').readAsStringSync()) as Map,
    );
    expect(bi('Settings', 'செட்டிங்ஸ்'), hindi['Settings']);
    // Values inside a message are kept, in the translation's own order.
    final template = hindi['{0} people want to join your ranch']!;
    expect(
      bi('7 people want to join your ranch', '7 பேர்'),
      template.replaceAll('{0}', '7'),
    );
    // Text that is not an app message (a name, a number) stays as it is.
    expect(tr('Selvakumar'), 'Selvakumar');
    await Hive.box('settings').put('languageMode', 'English');
  });
}
