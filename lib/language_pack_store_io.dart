import 'dart:io';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import 'language_packs.dart';

/// Hive box with the installed versions (pack id → {version, size, path}).
const languagePackBox = 'language_packs';

/// Packs as files in the app's support folder: `language_packs/<id>/`.
/// A download goes to `<version>.part` and is renamed to `pack.bin` only
/// after its size and SHA-256 are checked, so a half file is never used.
class FilePackStore implements PackStore {
  FilePackStore._(this.root);
  final Directory root;

  static Future<FilePackStore> open() async {
    if (!Hive.isBoxOpen(languagePackBox)) await Hive.openBox(languagePackBox);
    final support = await getApplicationSupportDirectory();
    final root = Directory('${support.path}/language_packs');
    await root.create(recursive: true);
    return FilePackStore._(root);
  }

  Box get _box => Hive.box(languagePackBox);

  Directory folder(String id) =>
      Directory('${root.path}/${id.replaceAll(RegExp(r'[^\w.-]'), '_')}');

  /// The installed file of a pack, for the offline engine.
  File? file(String id) {
    if (installedVersion(id) == null) return null;
    final f = File('${folder(id).path}/pack.bin');
    return f.existsSync() ? f : null;
  }

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

  @override
  Future<PackWriter> begin(LangPack pack) async {
    final dir = folder(pack.id);
    await dir.create(recursive: true);
    final part = File('${dir.path}/${pack.version}.part');
    return _FileWriter(
      this,
      pack,
      part,
      part.existsSync() ? part.lengthSync() : 0,
    );
  }

  @override
  Future<void> remove(String id) async {
    await _box.delete(id);
    final dir = folder(id);
    if (dir.existsSync()) await dir.delete(recursive: true);
  }
}

class _FileWriter implements PackWriter {
  _FileWriter(this.store, this.pack, this.part, this.existingLength);
  final FilePackStore store;
  final LangPack pack;
  final File part;
  @override
  final int existingLength;
  IOSink? _sink;

  @override
  Stream<List<int>> existing() => existingLength == 0
      ? const Stream.empty()
      : part.openRead(0, existingLength);

  @override
  Future<void> add(List<int> chunk) async {
    _sink ??= part.openWrite(mode: FileMode.append);
    _sink!.add(chunk);
  }

  Future<void> _close() async {
    final sink = _sink;
    _sink = null;
    if (sink != null) {
      await sink.flush();
      await sink.close();
    }
  }

  @override
  Future<void> commit(int version) async {
    await _close();
    final target = File('${store.folder(pack.id).path}/pack.bin');
    if (target.existsSync()) await target.delete();
    await part.rename(target.path);
    await store._box.put(pack.id, {
      'version': version,
      'language': pack.language,
      'kind': pack.kind.name,
      'size': pack.sizeBytes,
      'path': target.path,
      'installedAt': DateTime.now().toIso8601String(),
    });
  }

  @override
  Future<void> abort({bool keepPartial = false}) async {
    await _close();
    if (!keepPartial && part.existsSync()) await part.delete();
  }
}

/// Opens this device's store.
Future<PackStore> openPackStore() => FilePackStore.open();

/// Kinds this device can use: all of them on phones.
const Set<PackKind>? devicePackKinds = null;
