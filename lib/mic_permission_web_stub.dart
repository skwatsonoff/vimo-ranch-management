import 'mic_permission.dart';

/// Not a browser build: the native backend is used instead.
MicPermissionBackend webMicPermissionBackend() =>
    const UnsupportedMicPermissionBackend();
