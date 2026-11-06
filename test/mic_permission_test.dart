import 'package:flutter_test/flutter_test.dart';
import 'package:ranch_management/mic_permission.dart';

import 'fake_mic_backend.dart';

void main() {
  final events = <String>[];
  setUp(() {
    events.clear();
    MicPermission.log = (type, details) =>
        events.add('$type ${details['state'] ?? ''}'.trim());
  });
  tearDown(() => MicPermission.log = null);

  test('granted: no pop-up is shown', () async {
    final fake = FakeMicBackend(statuses: [MicAccess.granted]);
    MicPermission.backend = fake;
    expect(await ensureMicPermission(), MicAccess.granted);
    expect(fake.requestCalls, 0);
    expect(events, ['mic_permission_status granted']);
  });

  test('denied, then allowed in the pop-up', () async {
    final fake = FakeMicBackend(
      statuses: [MicAccess.denied],
      requests: [MicAccess.granted],
    );
    MicPermission.backend = fake;
    expect(await ensureMicPermission(speech: true), MicAccess.granted);
    expect(fake.requestCalls, 1);
    expect(events, [
      'mic_permission_status denied',
      'mic_permission_request granted',
    ]);
  });

  test('taken back later ("Only this time"): asked again next time', () async {
    final fake = FakeMicBackend(
      statuses: [MicAccess.granted, MicAccess.denied],
      requests: [MicAccess.granted],
    );
    MicPermission.backend = fake;
    expect(await ensureMicPermission(), MicAccess.granted);
    expect(await ensureMicPermission(), MicAccess.granted);
    expect(fake.requestCalls, 1);
  });

  test('permanently denied: no pop-up, Settings is the only way', () async {
    final fake = FakeMicBackend(statuses: [MicAccess.permanentlyDenied]);
    MicPermission.backend = fake;
    final access = await ensureMicPermission();
    expect(access, MicAccess.permanentlyDenied);
    expect(access.needsSettings, isTrue);
    expect(fake.requestCalls, 0);
    expect(await openMicSettings(), isTrue);
    expect(fake.settingsCalls, 1);
  });

  test('denied twice in the pop-up becomes permanently denied', () async {
    final fake = FakeMicBackend(
      statuses: [MicAccess.denied],
      requests: [MicAccess.denied, MicAccess.permanentlyDenied],
    );
    MicPermission.backend = fake;
    expect(await ensureMicPermission(), MicAccess.denied);
    expect(await ensureMicPermission(), MicAccess.permanentlyDenied);
  });

  test('checking only never shows a pop-up', () async {
    final fake = FakeMicBackend(statuses: [MicAccess.denied]);
    MicPermission.backend = fake;
    expect(await ensureMicPermission(ask: false), MicAccess.denied);
    expect(fake.requestCalls, 0);
  });

  test('a failing plugin is reported as denied, not a crash', () async {
    MicPermission.backend = _ThrowingBackend();
    expect(await ensureMicPermission(), MicAccess.denied);
    expect(events.first, startsWith('mic_permission_error'));
  });

  test('browser states: blocked, prompt and allowed', () {
    expect(micAccessFromBrowserState('granted'), MicAccess.granted);
    expect(micAccessFromBrowserState('prompt'), MicAccess.denied);
    expect(micAccessFromBrowserState(null), MicAccess.denied);
    expect(micAccessFromBrowserState('denied'), MicAccess.permanentlyDenied);
  });
}

class _ThrowingBackend implements MicPermissionBackend {
  @override
  String get platform => 'android';
  @override
  Future<MicAccess> status({bool speech = false}) => throw StateError('no');
  @override
  Future<MicAccess> request({bool speech = false}) => throw StateError('no');
  @override
  Future<bool> openSettings() async => false;
}
