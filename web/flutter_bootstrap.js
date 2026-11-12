{{flutter_js}}
{{flutter_build_config}}

(async function () {
  try {
    // Release builds serve the pinned Firebase modules from the app shell.
    // FlutterFire loads the CDN normally in development builds.
    await import('./firebase-sdk.js');
  } catch (_) {
    // FlutterFire handles initialization if the release module is absent.
  }
  await _flutter.loader.load({ config: { canvasKitBaseUrl: 'canvaskit/' } });
})();
