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

  void dismissBootSplash() {}

  void start({
    required void Function() onOnline,
    required void Function() onFocus,
  }) {}

  void stop() {}
}
