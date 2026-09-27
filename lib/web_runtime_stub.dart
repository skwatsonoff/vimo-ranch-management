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

  void start({
    required void Function() onOnline,
    required void Function() onFocus,
  }) {}

  void stop() {}
}
