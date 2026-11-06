import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'mic_permission.dart';

MicPermissionBackend webMicPermissionBackend() =>
    const WebMicPermissionBackend();

/// Browsers: the Permissions API to read the state, getUserMedia to show the
/// pop-up. Once a site is "Blocked" the browser never shows the pop-up again;
/// only the lock icon next to the address can allow it.
class WebMicPermissionBackend implements MicPermissionBackend {
  const WebMicPermissionBackend();

  @override
  String get platform => 'web';

  /// 'granted', 'prompt', 'denied', or null when the browser cannot say
  /// (older Safari and Firefox throw for "microphone").
  Future<String?> _query() async {
    try {
      final descriptor = JSObject()
        ..setProperty('name'.toJS, 'microphone'.toJS);
      final result = await web.window.navigator.permissions
          .query(descriptor)
          .toDart;
      return result.state;
    } catch (_) {
      return null;
    }
  }

  bool get _hasMediaDevices {
    try {
      return (web.window.navigator as JSObject)
          .hasProperty('mediaDevices'.toJS)
          .toDart;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<MicAccess> status({bool speech = false}) async {
    if (!_hasMediaDevices) return MicAccess.unsupported;
    return micAccessFromBrowserState(await _query());
  }

  @override
  Future<MicAccess> request({bool speech = false}) async {
    if (!_hasMediaDevices) return MicAccess.unsupported;
    try {
      final constraints = web.MediaStreamConstraints(audio: true.toJS);
      final stream = await web.window.navigator.mediaDevices
          .getUserMedia(constraints)
          .toDart;
      // Only the permission was wanted: release the microphone at once.
      for (final track in stream.getTracks().toDart) {
        track.stop();
      }
      return MicAccess.granted;
    } catch (_) {
      final state = await _query();
      if (state == 'denied') return MicAccess.permanentlyDenied;
      // Chrome blocks quietly after a few dismissals and reports "prompt".
      return state == 'granted' ? MicAccess.granted : MicAccess.denied;
    }
  }

  /// A page cannot open the browser's site settings; the screen shows the
  /// steps instead.
  @override
  Future<bool> openSettings() async => false;
}
