// Dart side of web/vimo_ear.js.
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('vimoEar')
external _Ear? get _ear;

extension type _Ear(JSObject _) implements JSObject {
  external bool supported();
  external JSPromise<JSBoolean> isCached(String name);
  external JSPromise<JSBoolean> isAvailable(String name);
  external JSPromise<JSBoolean> prepare(String name, JSFunction onProgress);
  external JSPromise<JSBoolean> start(
    String name,
    String lang,
    JSObject cbs,
    String words,
  );
  external void pause();
  external void close();
}

bool earSupported() {
  try {
    return _ear?.supported() ?? false;
  } catch (_) {
    return false;
  }
}

Future<bool> earCached(String model) async {
  final ear = _ear;
  if (ear == null) return false;
  try {
    return (await ear.isCached(model).toDart).toDart;
  } catch (_) {
    return false;
  }
}

Future<bool> earAvailable(String model) async {
  final ear = _ear;
  if (ear == null) return false;
  try {
    return (await ear.isAvailable(model).toDart).toDart;
  } catch (_) {
    return false;
  }
}

Future<void> earPrepare(String model, void Function(double) onProgress) async {
  final ear = _ear;
  if (ear == null) throw StateError('VIMO ear script is missing');
  await ear
      .prepare(
        model,
        ((JSAny? fraction) {
          if (fraction.isA<JSNumber>()) {
            onProgress((fraction as JSNumber).toDartDouble);
          }
        }).toJS,
      )
      .toDart;
}

Future<void> earStart(
  String model,
  String language, {
  String keywords = '',
  required void Function(String text, int ms, double seconds) onText,
  required void Function(double level) onLevel,
  required void Function(String code) onError,
  void Function(bool thinking)? onThinking,
}) async {
  final ear = _ear;
  if (ear == null) throw StateError('VIMO ear script is missing');
  final cbs = JSObject();
  cbs['onText'] = ((JSString raw) {
    final m = jsonDecode(raw.toDart) as Map<String, dynamic>;
    onText(
      '${m['text'] ?? ''}',
      (m['ms'] as num?)?.toInt() ?? 0,
      (m['seconds'] as num?)?.toDouble() ?? 0,
    );
  }).toJS;
  cbs['onLevel'] = ((JSNumber level) => onLevel(level.toDartDouble)).toJS;
  cbs['onError'] = ((JSString code) => onError(code.toDart)).toJS;
  cbs['onThinking'] = ((JSAny? on) => onThinking?.call(
    on.isA<JSBoolean>() && (on as JSBoolean).toDart,
  )).toJS;
  await ear.start(model, language, cbs, keywords).toDart;
}

void earPause() {
  try {
    _ear?.pause();
  } catch (_) {}
}

void earClose() {
  try {
    _ear?.close();
  } catch (_) {}
}
