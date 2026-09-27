part of 'main.dart';

/// Account-scoped device archives never enter shared backups or cloud uploads.
class DeviceWorkspaces {
  static const _scopedKeys = {
    'workspaceSyncEnabled',
    'pendingSettingKeys',
    'settingsQueueInitialized',
    'pendingAnimalEntryUpdates',
  };
  static Future<Box> get _archive async => Hive.isBoxOpen('device_workspaces')
      ? Hive.box('device_workspaces')
      : await Hive.openBox('device_workspaces');
  static String get scope =>
      '${settingText('firebaseUid', 'local')}:${ranchId()}';
  static Future<void> preserve() async {
    // Personal (no-ranch) workspaces are archived as well, under "uid:".
    if (Hive.box('settings').get('activeDeviceWorkspace') == '') {
      return;
    }
    final store = await _archive;
    await store.put(scope, {
      'boxes': {
        for (final name in backupBoxNames)
          if (name != 'settings' && Hive.isBoxOpen(name))
            name: Hive.box(name).toMap(),
      },
      'settings': {
        for (final entry in Hive.box('settings').toMap().entries)
          if (!CloudSyncService.isLocalSetting('${entry.key}') ||
              _scopedKeys.contains(entry.key))
            '${entry.key}': entry.value,
      },
    });
    await store.flush();
    await Hive.box('settings').put('activeDeviceWorkspace', '');
  }

  static Future<void> restore() async {
    final settings = Hive.box('settings');
    if (settings.get('activeDeviceWorkspace') == scope) return;
    final saved = asMap((await _archive).get(scope));
    AutoSyncService.beginRemoteWrite();
    try {
      if (saved.isNotEmpty) {
        final boxes = asMap(saved['boxes']);
        for (final name in backupBoxNames) {
          if (name == 'settings' ||
              !Hive.isBoxOpen(name) ||
              boxes[name] is! Map) {
            continue;
          }
          final box = Hive.box(name);
          await box.clear();
          await box.putAll(boxes[name] as Map);
        }
        for (final entry in asMap(saved['settings']).entries) {
          await AutoSyncService.putRemote(settings, entry.key, entry.value);
        }
      } else {
        await settings.put('workspaceSyncEnabled', false);
      }
      await settings.put('activeDeviceWorkspace', scope);
    } finally {
      AutoSyncService.endRemoteWrite();
    }
  }
}
