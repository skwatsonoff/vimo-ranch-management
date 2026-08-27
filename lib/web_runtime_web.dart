import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

class BrowserRuntime {
  JSFunction? _onlineListener;
  JSFunction? _focusListener;

  bool get online => web.window.navigator.onLine;

  void dismissBootSplash() {
    final loading = web.document.getElementById('loading') as web.HTMLElement?;
    if (loading == null) return;
    loading.style
      ..transition = 'opacity 260ms ease'
      ..opacity = '0';
    Timer(const Duration(milliseconds: 300), () => loading.remove());
  }

  Future<String?> pickImageDataUrl() async {
    final input = web.HTMLInputElement()
      ..type = 'file'
      ..accept = 'image/jpeg,image/png,image/webp,image/gif';
    final completer = Completer<String?>();

    late final JSFunction changeListener;
    late final JSFunction cancelListener;
    late final JSFunction focusListener;

    void finish(String? value) {
      if (!completer.isCompleted) completer.complete(value);
      input.removeEventListener('change', changeListener);
      input.removeEventListener('cancel', cancelListener);
      web.window.removeEventListener('focus', focusListener);
    }

    changeListener = ((web.Event _) {
      final files = input.files;
      final file = files == null || files.length == 0 ? null : files.item(0);
      if (file == null || file.size > 8 * 1024 * 1024) {
        finish(null);
        return;
      }

      final reader = web.FileReader();
      late final JSFunction loadListener;
      late final JSFunction errorListener;
      loadListener = ((web.Event _) {
        final result = reader.result;
        final dartResult = result?.dartify();
        finish(dartResult is String ? dartResult : null);
        reader.removeEventListener('load', loadListener);
        reader.removeEventListener('error', errorListener);
      }).toJS;
      errorListener = ((web.Event _) {
        finish(null);
        reader.removeEventListener('load', loadListener);
        reader.removeEventListener('error', errorListener);
      }).toJS;
      reader.addEventListener('load', loadListener);
      reader.addEventListener('error', errorListener);
      reader.readAsDataURL(file);
    }).toJS;
    cancelListener = ((web.Event _) => finish(null)).toJS;
    // Some iOS PWA versions do not emit `cancel`. When the picker gives focus
    // back without a file, close the loading state instead of waiting minutes.
    focusListener = ((web.Event _) {
      Timer(const Duration(milliseconds: 900), () {
        final files = input.files;
        if (!completer.isCompleted && (files == null || files.length == 0)) {
          finish(null);
        }
      });
    }).toJS;

    input.addEventListener('change', changeListener);
    input.addEventListener('cancel', cancelListener);
    web.window.addEventListener('focus', focusListener);
    input.click();
    return completer.future.timeout(
      const Duration(seconds: 45),
      onTimeout: () {
        finish(null);
        return null;
      },
    );
  }

  void start({
    required void Function() onOnline,
    required void Function() onFocus,
  }) {
    stop();
    _onlineListener = ((web.Event _) => onOnline()).toJS;
    _focusListener = ((web.Event _) => onFocus()).toJS;
    web.window.addEventListener('online', _onlineListener);
    web.window.addEventListener('focus', _focusListener);
  }

  void stop() {
    final onlineListener = _onlineListener;
    final focusListener = _focusListener;
    if (onlineListener != null) {
      web.window.removeEventListener('online', onlineListener);
    }
    if (focusListener != null) {
      web.window.removeEventListener('focus', focusListener);
    }
    _onlineListener = null;
    _focusListener = null;
  }
}
