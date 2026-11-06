import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ranch_management/voice_engine.dart';
import 'package:speech_to_text_platform_interface/speech_to_text_platform_interface.dart';

class _Platform extends SpeechToTextPlatform {
  String? listenedLocale;
  bool? onDevice;
  List<String>? phrases;

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
    listenedLocale = localeId;
    this.onDevice = options?.onDevice;
    phrases = options?.contextualPhrases;
    onStatus?.call('listening');
    return true;
  }

  @override
  Future<void> stop() async {}
  @override
  Future<void> cancel() async {}
  @override
  Future<List<dynamic>> locales() async => ['en_IN:English', 'ta_IN:Tamil'];
  @override
  Future<bool> hasOnDeviceSupport({String? localeId}) async =>
      localeId == 'ta_IN';
}

class _FakeEngine implements VoiceEngine {
  _FakeEngine(this.name, {this.startsOk = true});
  @override
  final String name;
  final bool startsOk;
  bool disposed = false;
  @override
  final Map<String, Object?> facts = {};
  @override
  bool get isOffline => name == 'offline';
  @override
  bool get isListening => false;
  @override
  Future<bool> initialize() async => startsOk;
  @override
  Future<List<String>> supportedLocales() async => const [];
  @override
  Future<void> start({
    required String locale,
    List<String> hotwords = const [],
    Duration pauseFor = const Duration(seconds: 12),
    Duration listenFor = const Duration(seconds: 55),
  }) async {}
  @override
  void changePauseFor(Duration pause) {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> cancel() async {}
  @override
  Stream<VoiceHeard> get results => const Stream.empty();
  @override
  Stream<double> get soundLevels => const Stream.empty();
  @override
  Stream<VoiceEngineError> get errors => const Stream.empty();
  @override
  Stream<String> get statuses => const Stream.empty();
  @override
  Future<void> dispose() async => disposed = true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final logs = <String>[];
  void log(String type, Map<String, Object?> d) =>
      logs.add('$type ${d['engine'] ?? d['reason'] ?? ''}'.trim());
  setUp(logs.clear);

  test('offline voice off: the system engine, as today', () async {
    final (engine, ok) = await createVoiceEngine(
      offlineEnabled: false,
      offlineModelPath: '/packs/asr-ta/pack.bin',
      system: () => _FakeEngine('system'),
      offline: (_) => _FakeEngine('offline'),
      log: log,
    );
    expect(engine.name, 'system');
    expect(ok, isTrue);
    expect(logs, ['engine system']);
  });

  test('offline on but no pack installed: system engine', () async {
    final (engine, _) = await createVoiceEngine(
      offlineEnabled: true,
      system: () => _FakeEngine('system'),
      log: log,
    );
    expect(engine.name, 'system');
    expect(logs.first, 'engine_fallback offline pack not installed');
  });

  test('offline engine not built in yet: falls back to system', () async {
    final (engine, _) = await createVoiceEngine(
      offlineEnabled: true,
      offlineModelPath: '/packs/asr-ta/pack.bin',
      system: () => _FakeEngine('system'),
      log: log,
    );
    expect(engine.name, 'system');
    expect(logs.first, startsWith('engine_fallback VIMO offline voice'));
  });

  test('offline engine that starts is used', () async {
    final offline = _FakeEngine('offline');
    final (engine, ok) = await createVoiceEngine(
      offlineEnabled: true,
      offlineModelPath: '/packs/asr-ta/pack.bin',
      system: () => _FakeEngine('system'),
      offline: (_) => offline,
      log: log,
    );
    expect(engine, same(offline));
    expect(ok, isTrue);
    expect(engine.isOffline, isTrue);
  });

  test(
    'an offline engine that does not start is closed, then system',
    () async {
      final offline = _FakeEngine('offline', startsOk: false);
      final (engine, _) = await createVoiceEngine(
        offlineEnabled: true,
        offlineModelPath: '/packs/asr-ta/pack.bin',
        system: () => _FakeEngine('system'),
        offline: (_) => offline,
        log: log,
      );
      expect(engine.name, 'system');
      expect(offline.disposed, isTrue);
    },
  );

  test('system engine: phone spelling of Tamil, on-device when offered, '
      'hotwords passed', () async {
    final platform = _Platform();
    SpeechToTextPlatform.instance = platform;
    final engine = SystemSpeechEngine();
    expect(await engine.initialize(), isTrue);
    expect(await engine.supportedLocales(), ['en_IN', 'ta_IN']);
    await engine.start(locale: 'ta-IN', hotwords: const ['Vimo', 'Lakshmi']);
    expect(platform.listenedLocale, 'ta_IN');
    expect(platform.onDevice, isTrue);
    expect(platform.phrases, ['Vimo', 'Lakshmi']);
    expect(engine.facts['onDevice'], isTrue);
    await engine.start(locale: 'en-IN');
    expect(platform.listenedLocale, 'en_IN');
    expect(platform.onDevice, isFalse);
    await engine.dispose();
  });
}
