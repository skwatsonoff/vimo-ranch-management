import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter/material.dart' hide Ink;
import 'package:ranch_management/language_packs.dart';
import 'package:ranch_management/main.dart' show LanguagePacksScreen;

List<int> bytesOf(String name, int size) =>
    List<int>.generate(size, (i) => (i * 7 + name.length) % 251);

Map<String, Object?> packJson(
  String id,
  String language,
  String kind,
  int version,
  List<int> data, {
  String? sha,
}) => {
  'id': id,
  'language': language,
  'kind': kind,
  'version': version,
  'url': 'https://packs.test/$id-$version.bin',
  'sizeBytes': data.length,
  'sha256': sha ?? sha256.convert(data).toString(),
};

/// A fake Firebase Storage: the manifest plus pack files, with Range
/// support and a count of requests.
class FakeStorage {
  FakeStorage(this.files, this.manifest);
  final Map<String, List<int>> files;
  Map<String, Object?> manifest;
  final requests = <String>[];
  int? failAfter;

  MockClient get client => MockClient.streaming((request, _) async {
    final url = request.url.toString();
    requests.add('${request.headers['Range'] ?? ''} $url'.trim());
    if (url == 'https://packs.test/manifest.json') {
      return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(manifest))),
        200,
      );
    }
    final name = url.split('/').last;
    final data = files[name];
    if (data == null) return http.StreamedResponse(const Stream.empty(), 404);
    final range = request.headers['Range'];
    var start = 0;
    var status = 200;
    if (range != null) {
      start = int.parse(range.replaceAll(RegExp(r'[^0-9]'), ''));
      status = 206;
    }
    final body = data.sublist(start);
    final cut = failAfter;
    Stream<List<int>> stream() async* {
      for (var i = 0; i < body.length; i += 100) {
        if (cut != null && start + i >= cut) {
          throw http.ClientException('connection lost');
        }
        yield body.sublist(i, (i + 100).clamp(0, body.length));
      }
    }

    return http.StreamedResponse(stream(), status);
  });
}

void main() {
  final ta = bytesOf('ta', 1000);
  final en = bytesOf('en', 600);
  final tanglish = bytesOf('tl', 400);
  final hi = bytesOf('hi', 300);

  Map<String, Object?> manifest({int taVersion = 1, String? taSha}) => {
    'schema': 1,
    'bundles': {
      'ta': ['ta', 'en', 'ta-Latn'],
    },
    'packs': [
      packJson('asr-ta', 'ta', 'asr', taVersion, ta, sha: taSha),
      packJson('asr-en', 'en', 'asr', 1, en),
      packJson('lex-ta-Latn', 'ta-Latn', 'lexicon', 1, tanglish),
      packJson('asr-hi', 'hi', 'asr', 1, hi),
    ],
  };

  FakeStorage storage({int taVersion = 1, String? taSha}) => FakeStorage({
    'asr-ta-$taVersion.bin': ta,
    'asr-en-1.bin': en,
    'lex-ta-Latn-1.bin': tanglish,
    'asr-hi-1.bin': hi,
  }, manifest(taVersion: taVersion, taSha: taSha));

  LanguagePackManager manager(FakeStorage s, PackStore store) =>
      LanguagePackManager(
        store,
        manifestUrl: 'https://packs.test/manifest.json',
        client: s.client,
      );

  test('bundles: Tamil brings English and Tanglish; others bring English', () {
    final m = PackManifest.parse(jsonEncode(manifest()));
    expect(m.languagesFor('ta'), ['ta', 'en', 'ta-Latn']);
    expect(m.languagesFor('hi'), ['hi', 'en']);
    expect(m.languagesFor('en'), ['en']);
    expect(m.packsFor('ta').map((p) => p.id).toSet(), {
      'asr-ta',
      'asr-en',
      'lex-ta-Latn',
    });
    expect(m.packsFor('ta', kinds: {PackKind.lexicon}).map((p) => p.id), [
      'lex-ta-Latn',
    ]);
  });

  test(
    'install reports progress to 1.0 and makes the language ready',
    () async {
      final s = storage();
      final store = MemoryPackStore();
      final m = manager(s, store);
      expect(await m.isReady('ta'), isFalse);
      final progress = await m.install('ta').toList();
      expect(progress.first.fraction, 0);
      expect(progress.last.fraction, 1.0);
      expect(progress.last.total, 2000);
      for (var i = 1; i < progress.length; i++) {
        expect(progress[i].done, greaterThanOrEqualTo(progress[i - 1].done));
      }
      expect(store.files['asr-ta'], ta);
      expect(await m.isReady('ta'), isTrue);
    },
  );

  test('a second install downloads nothing', () async {
    final s = storage();
    final store = MemoryPackStore();
    await manager(s, store).install('ta').drain<void>();
    final before = s.requests.where((r) => r.endsWith('.bin')).length;
    await manager(s, store).install('ta').drain<void>();
    expect(s.requests.where((r) => r.endsWith('.bin')).length, before);
  });

  test('a newer version in the manifest is fetched again', () async {
    final store = MemoryPackStore();
    await manager(storage(), store).install('ta').drain<void>();
    final newer = storage(taVersion: 2);
    final m = manager(newer, store);
    expect((await m.missing('ta')).map((p) => p.id), ['asr-ta']);
    await m.install('ta').drain<void>();
    expect(store.installedVersion('asr-ta'), 2);
    expect(newer.requests.where((r) => r.endsWith('.bin')), [
      'https://packs.test/asr-ta-2.bin',
    ]);
  });

  test('a corrupted download keeps nothing', () async {
    final store = MemoryPackStore();
    final m = manager(storage(taSha: 'deadbeef'), store);
    await expectLater(
      m.install('ta').drain<void>(),
      throwsA(isA<PackException>()),
    );
    expect(store.installedVersion('asr-ta'), isNull);
    expect(store.partials, isEmpty);
  });

  test('remove keeps English and packs another language needs', () async {
    final store = MemoryPackStore();
    final s = storage();
    final m = manager(s, store);
    await m.install('ta').drain<void>();
    await m.install('hi').drain<void>();
    final removed = await m.remove('ta', keepFor: ['hi']);
    expect(removed.toSet(), {'asr-ta', 'lex-ta-Latn'});
    expect(store.installedVersion('asr-en'), 1);
    expect(store.installedVersion('asr-hi'), 1);
  });

  test('an interrupted download continues from where it stopped', () async {
    final store = MemoryPackStore();
    final s = storage()..failAfter = 500;
    final m = manager(s, store);
    await expectLater(m.install('hi').drain<void>(), throwsA(anything));
    // Part of asr-hi or asr-en is kept for the next attempt.
    expect(store.partials, isNotEmpty);
    s.failAfter = null;
    await manager(s, store).install('hi').drain<void>();
    expect(s.requests.any((r) => r.startsWith('bytes=')), isTrue);
    expect(store.files['asr-hi'], hi);
    expect(store.files['asr-en'], en);
    expect(store.partials, isEmpty);
  });

  test('no manifest published yet is a clear error, not a crash', () async {
    final m = LanguagePackManager(
      MemoryPackStore(),
      manifestUrl: 'https://packs.test/missing.json',
      client: MockClient((_) async => http.Response('', 404)),
    );
    expect(await m.isReady('ta'), isFalse);
    await expectLater(m.missing('ta'), throwsA(isA<PackException>()));
  });

  testWidgets('the packs screen downloads and shows ready offline', (
    tester,
  ) async {
    final store = MemoryPackStore();
    final s = storage();
    final m = manager(s, store);
    await tester.pumpWidget(MaterialApp(home: LanguagePacksScreen(manager: m)));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    // English needs only the English pack.
    expect(find.textContaining('1 packs'), findsOneWidget);
    await tester.tap(find.text('Download'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    expect(find.text('Ready offline'), findsOneWidget);
    expect(store.installedVersion('asr-en'), 1);
    expect(tester.takeException(), isNull);
  });
}
