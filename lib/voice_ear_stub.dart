// The ear exists only in the browser (web/vimo_ear.js).
bool earSupported() => false;
Future<bool> earCached(String model) async => false;
Future<bool> earAvailable(String model) async => false;
Future<void> earPrepare(String model, void Function(double) onProgress) =>
    Future.error(UnsupportedError('VIMO ear runs in the browser only'));
Future<void> earStart(
  String model,
  String language, {
  String keywords = '',
  required void Function(String text, int ms, double seconds) onText,
  required void Function(double level) onLevel,
  required void Function(String code) onError,
  void Function(bool thinking)? onThinking,
}) => Future.error(UnsupportedError('VIMO ear runs in the browser only'));
void earPause() {}
void earClose() {}
