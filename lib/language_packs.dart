/// Language packs: what VIMO downloads so voice works without the internet.
///
/// A pack is one file for one language and one job (speech recognition,
/// understanding, the speaking voice, app text, or the owner's own words).
/// The manifest on Firebase Storage lists every pack with its version, size
/// and SHA-256; a phone downloads only what its language needs and checks
/// every byte before keeping it.
///
/// Pure Dart: no dart:io, so it runs on phones, the web and in tests.
library;

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// THE ONE PLACE TO EDIT: the public address of `manifest.json`. Packs are
/// assets of the repository's free "voice-packs" GitHub release, written by
/// the cloud training workflow; the app only reads them.
const languagePackManifestUrl =
    'https://github.com/skwatsonoff/vimo-ranch-management/releases/download/voice-packs/manifest.json';

/// What a pack is for.
enum PackKind {
  /// Speech recognition model (hears words).
  asr,

  /// Understanding model (sentence → intent).
  nlu,

  /// Speaking voice.
  tts,

  /// App text.
  strings,

  /// Words: cow names, village and dairy words, the owner's learned words.
  lexicon,
}

PackKind? _kind(String name) {
  for (final k in PackKind.values) {
    if (k.name == name) return k;
  }
  return null;
}

/// One downloadable file.
class LangPack {
  final String id;
  final String language;
  final PackKind kind;
  final int version;
  final String url;
  final int sizeBytes;
  final String sha256;

  const LangPack({
    required this.id,
    required this.language,
    required this.kind,
    required this.version,
    required this.url,
    required this.sizeBytes,
    required this.sha256,
  });

  static LangPack fromJson(Map<String, dynamic> json) {
    final kind = _kind('${json['kind']}');
    if (kind == null) throw PackException('Unknown pack kind ${json['kind']}');
    return LangPack(
      id: '${json['id']}',
      language: '${json['language']}',
      kind: kind,
      version: (json['version'] as num).toInt(),
      url: '${json['url']}',
      sizeBytes: (json['sizeBytes'] as num).toInt(),
      sha256: '${json['sha256']}'.toLowerCase(),
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'language': language,
    'kind': kind.name,
    'version': version,
    'url': url,
    'sizeBytes': sizeBytes,
    'sha256': sha256,
  };
}

/// The list of packs and which languages each app language needs.
class PackManifest {
  final int schema;
  final List<LangPack> packs;

  /// App language → pack languages, e.g. "ta" → ["ta", "en", "ta-Latn"].
  final Map<String, List<String>> bundles;

  const PackManifest({
    required this.schema,
    required this.packs,
    required this.bundles,
  });

  static PackManifest parse(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } catch (_) {
      throw const PackException('The pack list is not valid JSON');
    }
    if (decoded is! Map) throw const PackException('The pack list is empty');
    final bundles = <String, List<String>>{};
    final rawBundles = decoded['bundles'];
    if (rawBundles is Map) {
      rawBundles.forEach((k, v) {
        if (v is List) bundles['$k'] = [for (final l in v) '$l'];
      });
    }
    return PackManifest(
      schema: (decoded['schema'] as num?)?.toInt() ?? 1,
      packs: [
        for (final p in (decoded['packs'] as List? ?? const []))
          if (p is Map) LangPack.fromJson(Map<String, dynamic>.from(p)),
      ],
      bundles: bundles,
    );
  }

  /// The pack languages app language [code] needs: its bundle, or itself
  /// plus English. English alone needs only English.
  List<String> languagesFor(String code) {
    final bundle = bundles[code];
    if (bundle != null && bundle.isNotEmpty) return bundle;
    if (code == 'en') return const ['en'];
    return [code, 'en'];
  }

  /// The newest pack of each id for [code]'s languages.
  List<LangPack> packsFor(String code, {Set<PackKind>? kinds}) {
    final languages = languagesFor(code).toSet();
    final newest = <String, LangPack>{};
    for (final p in packs) {
      if (!languages.contains(p.language)) continue;
      if (kinds != null && !kinds.contains(p.kind)) continue;
      final old = newest[p.id];
      if (old == null || p.version > old.version) newest[p.id] = p;
    }
    return newest.values.toList();
  }
}

class PackException implements Exception {
  final String message;
  const PackException(this.message);
  @override
  String toString() => 'PackException: $message';
}

// --- storage ---------------------------------------------------------------------

/// Receives one pack's bytes. Nothing counts as installed until [commit].
abstract class PackWriter {
  /// Bytes already kept from an earlier, interrupted download of this
  /// version (a download can continue from here).
  int get existingLength;

  /// Those bytes, to check the whole file's SHA-256 after continuing.
  Stream<List<int>> existing();

  Future<void> add(List<int> chunk);

  /// Makes the pack installed at [version], replacing any older one.
  Future<void> commit(int version);

  /// Throws away this download. With [keepPartial] the bytes stay so the
  /// next attempt can continue.
  Future<void> abort({bool keepPartial = false});
}

/// Where packs live: files on phones, memory in tests.
abstract class PackStore {
  int? installedVersion(String id);
  Future<PackWriter> begin(LangPack pack);
  Future<void> remove(String id);

  /// Installed pack ids with their versions.
  Map<String, int> installed();
}

class MemoryPackStore implements PackStore {
  final Map<String, int> versions = {};
  final Map<String, List<int>> files = {};

  /// Interrupted downloads, by "id@version".
  final Map<String, List<int>> partials = {};

  @override
  int? installedVersion(String id) => versions[id];

  @override
  Map<String, int> installed() => Map.of(versions);

  @override
  Future<PackWriter> begin(LangPack pack) async =>
      _MemoryWriter(this, pack.id, '${pack.id}@${pack.version}');

  @override
  Future<void> remove(String id) async {
    versions.remove(id);
    files.remove(id);
  }
}

class _MemoryWriter implements PackWriter {
  _MemoryWriter(this.store, this.id, this.partialKey)
    : bytes = [...?store.partials[partialKey]];
  final MemoryPackStore store;
  final String id;
  final String partialKey;
  final List<int> bytes;
  late final int _existing = bytes.length;

  @override
  int get existingLength => _existing;

  @override
  Stream<List<int>> existing() => Stream.value(bytes.sublist(0, _existing));

  @override
  Future<void> add(List<int> chunk) async => bytes.addAll(chunk);

  @override
  Future<void> commit(int version) async {
    store.files[id] = List.of(bytes);
    store.versions[id] = version;
    store.partials.remove(partialKey);
  }

  @override
  Future<void> abort({bool keepPartial = false}) async {
    if (keepPartial) {
      store.partials[partialKey] = List.of(bytes);
    } else {
      store.partials.remove(partialKey);
    }
  }
}

// --- downloading --------------------------------------------------------------------

/// How far an install has come, over all its packs.
class PackProgress {
  final int done;
  final int total;
  final String? packId;
  const PackProgress(this.done, this.total, [this.packId]);

  double get fraction => total <= 0 ? 1 : (done / total).clamp(0.0, 1.0);
}

class LanguagePackManager {
  LanguagePackManager(
    this.store, {
    this.manifestUrl = languagePackManifestUrl,
    http.Client? client,
    this.kinds,
  }) : client = client ?? http.Client();

  final PackStore store;
  final String manifestUrl;
  final http.Client client;

  /// The kinds this device can use (the web has no offline recogniser).
  final Set<PackKind>? kinds;

  PackManifest? _manifest;
  bool _cancelled = false;

  Future<PackManifest> manifest({bool refresh = false}) async {
    final cached = _manifest;
    if (cached != null && !refresh) return cached;
    final http.Response response;
    try {
      response = await client.get(Uri.parse(manifestUrl));
    } catch (_) {
      throw const PackException('No internet: the pack list could not load');
    }
    if (response.statusCode != 200) {
      throw PackException(
        'The pack list is not published (${response.statusCode})',
      );
    }
    return _manifest = PackManifest.parse(utf8.decode(response.bodyBytes));
  }

  /// Packs [code] needs that are not installed at their newest version.
  Future<List<LangPack>> missing(String code) async {
    final m = await manifest();
    return [
      for (final p in m.packsFor(code, kinds: kinds))
        if ((store.installedVersion(p.id) ?? -1) < p.version) p,
    ];
  }

  Future<bool> isReady(String code) async {
    try {
      final m = await manifest();
      if (m.packsFor(code, kinds: kinds).isEmpty) return false;
      return (await missing(code)).isEmpty;
    } on PackException {
      return false;
    }
  }

  /// Stops the running install after its current chunk; what was
  /// downloaded stays so a retry can continue.
  void cancel() => _cancelled = true;

  /// Downloads and installs everything [code] needs, reporting one
  /// overall progress.
  Stream<PackProgress> install(String code) async* {
    _cancelled = false;
    final needed = await missing(code);
    final total = needed.fold<int>(0, (s, p) => s + p.sizeBytes);
    var done = 0;
    yield PackProgress(0, total);
    for (final pack in needed) {
      final writer = await store.begin(pack);
      var offset = writer.existingLength;
      if (offset > pack.sizeBytes) {
        await writer.abort();
        offset = 0;
      }
      final hash = _Sha256Sink();
      final request = http.Request('GET', Uri.parse(pack.url));
      if (offset > 0) request.headers['Range'] = 'bytes=$offset-';
      http.StreamedResponse response;
      try {
        response = await client.send(request);
      } catch (_) {
        await writer.abort(keepPartial: true);
        throw PackException('No internet while downloading ${pack.id}');
      }
      final PackWriter target;
      if (offset > 0 && response.statusCode == 206) {
        // The server continues where the last download stopped.
        await for (final chunk in writer.existing()) {
          hash.add(chunk);
        }
        target = writer;
      } else if (response.statusCode == 200) {
        // A fresh copy: forget any partial bytes.
        if (offset > 0) {
          await writer.abort();
          target = await store.begin(pack);
          offset = 0;
        } else {
          target = writer;
        }
      } else {
        await writer.abort(keepPartial: true);
        throw PackException(
          'Download of ${pack.id} failed (${response.statusCode})',
        );
      }
      var received = offset;
      done += offset;
      yield PackProgress(done, total, pack.id);
      try {
        await for (final chunk in response.stream) {
          if (_cancelled) {
            await target.abort(keepPartial: true);
            throw const PackException('Cancelled');
          }
          received += chunk.length;
          if (received > pack.sizeBytes) {
            await target.abort();
            throw PackException('${pack.id} is larger than the pack list says');
          }
          hash.add(chunk);
          await target.add(chunk);
          done += chunk.length;
          yield PackProgress(done, total, pack.id);
        }
      } on PackException {
        rethrow;
      } catch (error) {
        await target.abort(keepPartial: true);
        final text = '$error'.toLowerCase();
        throw PackException(
          text.contains('space') || text.contains('enospc')
              ? 'Not enough free space for ${pack.id}'
              : 'Download of ${pack.id} stopped',
        );
      }
      if (received != pack.sizeBytes) {
        await target.abort(keepPartial: true);
        throw PackException(
          '${pack.id} is incomplete ($received of ${pack.sizeBytes})',
        );
      }
      if (hash.close() != pack.sha256) {
        // A damaged file must never be used: keep nothing.
        await target.abort();
        throw PackException('${pack.id} failed its check and was not kept');
      }
      await target.commit(pack.version);
    }
    yield PackProgress(total, total);
  }

  /// Removes [code]'s packs, except English and packs that a language in
  /// [keepFor] still needs.
  Future<List<String>> remove(
    String code, {
    Iterable<String> keepFor = const [],
  }) async {
    final m = await manifest();
    final keepLanguages = {
      'en',
      for (final other in keepFor) ...m.languagesFor(other),
    };
    final removed = <String>[];
    for (final p in m.packsFor(code)) {
      if (keepLanguages.contains(p.language)) continue;
      if (store.installedVersion(p.id) == null) continue;
      await store.remove(p.id);
      removed.add(p.id);
    }
    return removed;
  }
}

/// SHA-256 over chunks as they arrive.
class _Sha256Sink {
  final _out = _DigestSink();
  late final ByteConversionSink _in = sha256.startChunkedConversion(_out);
  void add(List<int> chunk) => _in.add(chunk);
  String close() {
    _in.close();
    return _out.value.toString();
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
