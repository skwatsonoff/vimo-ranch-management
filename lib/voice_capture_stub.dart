import 'voice_capture.dart';

/// Away from the browser there is no web capture.
CaptureBackend? webCaptureBackend() => null;

/// Legacy downloaded speech models in this browser (none away from it).
Future<List<String>> legacyEarCaches() async => const [];
Future<int> removeLegacyEarCaches() async => 0;
