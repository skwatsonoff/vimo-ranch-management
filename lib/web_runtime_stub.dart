class BrowserRuntime {
  bool get online => true;

  Future<String?> pickImageDataUrl() async => null;

  void start({
    required void Function() onOnline,
    required void Function() onFocus,
  }) {}

  void stop() {}
}
