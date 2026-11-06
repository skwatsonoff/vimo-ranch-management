import 'dart:typed_data';

import 'package:hive_flutter/hive_flutter.dart';

import 'language_packs.dart';

/// Hive box with the installed versions and, on the web, the pack bytes.
const languagePackBox = 'language_packs';

/// The web keeps only small packs (words, app text, understanding) in the
/// browser's storage. A browser has no offline speech recogniser, so
/// recognition and voice packs are not downloaded here.
class BrowserPackStore implements PackStore {
  BrowserPackStore._();

  static Future<BrowserPackStore> open() async {
    if (!Hive.isBoxOpen(languagePackBox)) await Hive.openBox(languagePackBox);
    return BrowserPackStore._();
  }

  Box get _box => Hive.box(languagePackBox);

  @override
  int? installedVersion(String id) {
    final row = _box.get(id);
    return row is Map ? (row['version'] as num?)?.toInt() : null;
  }

  @override
  Map<String, int> installed() => {
    for (final key in _box.keys)
      if (installedVersion('$key') != null) '$key': installedVersion('$key')!,
  };

  /// The installed bytes of a pack.
  Uint8List? bytes(String id) {
    final row = _box.get(id);
    final data = row is Map ? row['bytes'] : null;
    return data is Uint8List ? data : null;
  }

  @override
  Future<PackWriter> begin(LangPack pack) async => _BrowserWriter(this, pack);

  @override
  Future<void> remove(String id) => _box.delete(id);
}

class _BrowserWriter implements PackWriter {
  _BrowserWriter(this.store, this.pack);
  final BrowserPackStore store;
  final LangPack pack;
  final BytesBuilder _bytes = BytesBuilder(copy: false);

  @override
  int get existingLength => 0;

  @override
  Stream<List<int>> existing() => const Stream.empty();

  @override
  Future<void> add(List<int> chunk) async => _bytes.add(chunk);

  @override
  Future<void> commit(int version) => store._box.put(pack.id, {
    'version': version,
    'language': pack.language,
    'kind': pack.kind.name,
    'size': pack.sizeBytes,
    'bytes': _bytes.takeBytes(),
    'installedAt': DateTime.now().toIso8601String(),
  });

  @override
  Future<void> abort({bool keepPartial = false}) async => _bytes.clear();
}

Future<PackStore> openPackStore() => BrowserPackStore.open();

/// A browser can use the small packs only.
const Set<PackKind> devicePackKinds = {
  PackKind.nlu,
  PackKind.strings,
  PackKind.lexicon,
};
