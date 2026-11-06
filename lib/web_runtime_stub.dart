import 'dart:typed_data';

class BrowserRuntime {
  bool get online => true;
  bool get notificationsGranted => false;

  Future<String?> pickImageDataUrl() async => null;

  Future<bool> requestNotificationPermission() async => false;

  void showNotification({
    required String title,
    required String body,
    required String tag,
  }) {}

  Future<String> saveImage(Uint8List bytes, String fileName) async =>
      'unsupported';

  void dismissBootSplash() {}

  void markAppReady() {}

  /// Native apps judge the phone by frame timing alone.
  bool get lowEndHint => false;

  /// The browser's description of itself; empty outside a browser.
  String get userAgent => '';

  /// iPhone or iPad browser (Safari, Chrome on iOS).
  bool get appleMobile => false;

  /// Opened from the Home Screen as an app, not in a browser tab.
  bool get standaloneApp => false;

  /// Reduce Transparency is reported only by browsers.
  bool get reducedTransparency => false;

  void watchReducedTransparency(void Function(bool reduced) onChange) {}

  void start({
    required void Function() onOnline,
    required void Function() onFocus,
  }) {}

  void stop() {}
}
