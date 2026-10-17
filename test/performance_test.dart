import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:ranch_management/main.dart';

void main() {
  late Directory dir;
  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('vimo_perf_');
    Hive.init(dir.path);
    await Hive.openBox('settings');
  });
  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('Automatic follows the phone; a choice in Settings wins', () async {
    final settings = Hive.box('settings');
    await settings.clear();
    expect(DevicePerformance.mode, 'auto');
    expect(DevicePerformance.fast, isFalse);

    await settings.put('lowEndDevice', true);
    expect(DevicePerformance.fast, isTrue);

    await settings.put('performanceMode', 'full');
    expect(DevicePerformance.fast, isFalse);

    await settings.put('performanceMode', 'fast');
    await settings.put('lowEndDevice', false);
    expect(DevicePerformance.fast, isTrue);

    await settings.put('performanceMode', 'something else');
    expect(DevicePerformance.mode, 'auto');
  });

  test('The effects choice stays on this phone and never syncs', () {
    expect(CloudSyncService.isLocalSetting('performanceMode'), isTrue);
    expect(CloudSyncService.isLocalSetting('lowEndDevice'), isTrue);
  });
}
