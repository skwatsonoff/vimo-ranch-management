/// The platform capture backend: web/vimo_mic.js in the browser, none
/// elsewhere (the native apps keep their system speech engine).
library;

export 'voice_capture_stub.dart'
    if (dart.library.js_interop) 'voice_capture_web.dart';
