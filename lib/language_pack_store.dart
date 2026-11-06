/// The pack store for this device: files on phones, the browser's storage
/// on the web.
library;

export 'language_pack_store_web.dart'
    if (dart.library.io) 'language_pack_store_io.dart';
