/// One place that checks and asks for the microphone, used by every screen
/// that records or listens (voice milk mode, voice notes, voice training).
///
/// Why this exists: the speech plugin remembers that it started once and
/// never asks again. When the phone later takes the permission back (Android
/// "Only this time", Android removing permissions of unused apps, a change in
/// iOS Settings, or the browser forgetting the site), VIMO said "permission
/// is off" but showed no pop-up, so the owner could not fix it from the app.
/// Now every listening session first asks [ensureMicPermission], which checks
/// the real permission and shows the system pop-up whenever it still can.
library;

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import 'mic_permission_web_stub.dart'
    if (dart.library.js_interop) 'mic_permission_web.dart';

/// What VIMO may do with the microphone right now.
enum MicAccess {
  /// Allowed: listening and recording can start.
  granted,

  /// Not allowed yet, but VIMO can ask again (the pop-up will show).
  denied,

  /// Refused for good: only the phone's or browser's settings can allow it.
  permanentlyDenied,

  /// Blocked by the phone itself (parental controls, work profile).
  restricted,

  /// This device or browser has no microphone access at all.
  unsupported,
}

extension MicAccessText on MicAccess {
  bool get isGranted => this == MicAccess.granted;

  /// Only the phone's settings can change it: show "Open Settings".
  bool get needsSettings =>
      this == MicAccess.permanentlyDenied || this == MicAccess.restricted;
}

/// A browser Permissions API state as [MicAccess]: "denied" means the site
/// is blocked (only site settings can change it); "prompt" or an unknown
/// answer means asking will show the pop-up.
MicAccess micAccessFromBrowserState(String? state) => switch (state) {
  'granted' => MicAccess.granted,
  'denied' => MicAccess.permanentlyDenied,
  _ => MicAccess.denied,
};

/// The platform side, replaceable in tests.
abstract class MicPermissionBackend {
  /// The current state, without showing anything.
  Future<MicAccess> status({bool speech = false});

  /// Shows the system pop-up when it can, and returns the new state.
  Future<MicAccess> request({bool speech = false});

  /// Opens the app's (or site's) settings page. False when it cannot.
  Future<bool> openSettings();

  /// Where this backend runs, for the diagnostics log.
  String get platform;
}

/// Phones (Android, iOS) through permission_handler.
class NativeMicPermissionBackend implements MicPermissionBackend {
  const NativeMicPermissionBackend();

  /// iOS needs a separate speech recognition permission; Android does not.
  bool _needsSpeech(bool speech) =>
      speech && defaultTargetPlatform == TargetPlatform.iOS;

  static MicAccess _map(PermissionStatus s) {
    if (s.isGranted || s.isLimited || s.isProvisional) return MicAccess.granted;
    if (s.isPermanentlyDenied) return MicAccess.permanentlyDenied;
    if (s.isRestricted) return MicAccess.restricted;
    return MicAccess.denied;
  }

  /// The stricter of the two: both must be allowed to listen.
  static MicAccess _worst(MicAccess a, MicAccess b) =>
      a.index >= b.index ? a : b;

  @override
  Future<MicAccess> status({bool speech = false}) async {
    var access = _map(await Permission.microphone.status);
    if (_needsSpeech(speech)) {
      access = _worst(access, _map(await Permission.speech.status));
    }
    return access;
  }

  @override
  Future<MicAccess> request({bool speech = false}) async {
    var access = _map(await Permission.microphone.request());
    if (access.isGranted && _needsSpeech(speech)) {
      access = _worst(access, _map(await Permission.speech.request()));
    }
    return access;
  }

  @override
  Future<bool> openSettings() => openAppSettings();

  @override
  String get platform => defaultTargetPlatform.name;
}

/// Unsupported desktop targets: say so instead of failing quietly.
class UnsupportedMicPermissionBackend implements MicPermissionBackend {
  const UnsupportedMicPermissionBackend();
  @override
  Future<MicAccess> status({bool speech = false}) async =>
      MicAccess.unsupported;
  @override
  Future<MicAccess> request({bool speech = false}) async =>
      MicAccess.unsupported;
  @override
  Future<bool> openSettings() async => false;
  @override
  String get platform => 'unsupported';
}

MicPermissionBackend _defaultBackend() {
  if (kIsWeb) return webMicPermissionBackend();
  return switch (defaultTargetPlatform) {
    TargetPlatform.android ||
    TargetPlatform.iOS ||
    TargetPlatform.windows ||
    TargetPlatform.macOS => const NativeMicPermissionBackend(),
    _ => const UnsupportedMicPermissionBackend(),
  };
}

/// Shared state: tests replace [backend] and listen with [log].
class MicPermission {
  MicPermission._();

  static MicPermissionBackend backend = _defaultBackend();

  /// Receives every check and its result (the voice diagnostics log).
  static void Function(String type, Map<String, Object?> details)? log;

  static void _log(String type, Map<String, Object?> details) {
    try {
      log?.call(type, {'platform': backend.platform, ...details});
    } catch (_) {}
  }
}

/// Makes sure the microphone may be used, asking with the system pop-up when
/// that is still possible. [speech] also covers speech recognition (iOS).
/// Set [ask] to false to only check, never show a pop-up.
Future<MicAccess> ensureMicPermission({
  bool speech = false,
  bool ask = true,
}) async {
  final backend = MicPermission.backend;
  MicAccess access;
  try {
    access = await backend.status(speech: speech);
  } catch (error) {
    MicPermission._log('mic_permission_error', {
      'step': 'status',
      'error': '$error',
    });
    access = MicAccess.denied;
  }
  MicPermission._log('mic_permission_status', {
    'speech': speech,
    'state': access.name,
  });
  if (access != MicAccess.denied || !ask) return access;
  try {
    access = await backend.request(speech: speech);
  } catch (error) {
    MicPermission._log('mic_permission_error', {
      'step': 'request',
      'error': '$error',
    });
    return MicAccess.denied;
  }
  MicPermission._log('mic_permission_request', {
    'speech': speech,
    'state': access.name,
  });
  return access;
}

/// Opens the settings page where the microphone can be allowed.
Future<bool> openMicSettings() async {
  try {
    final opened = await MicPermission.backend.openSettings();
    MicPermission._log('mic_open_settings', {'opened': opened});
    return opened;
  } catch (error) {
    MicPermission._log('mic_permission_error', {
      'step': 'open_settings',
      'error': '$error',
    });
    return false;
  }
}
