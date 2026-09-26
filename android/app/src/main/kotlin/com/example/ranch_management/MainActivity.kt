package com.example.ranch_management

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.view.KeyEvent

class MainActivity : FlutterActivity() {
    private var vendorVolumeEnabled = false
    private var volumeChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        volumeChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "vimo/vendor_volume")
        volumeChannel?.setMethodCallHandler { call, result ->
            if (call.method == "enabled") {
                vendorVolumeEnabled = call.arguments == true
                result.success(null)
            } else result.notImplemented()
        }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (vendorVolumeEnabled && (event.keyCode == KeyEvent.KEYCODE_VOLUME_UP || event.keyCode == KeyEvent.KEYCODE_VOLUME_DOWN)) {
            if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
                volumeChannel?.invokeMethod(if (event.keyCode == KeyEvent.KEYCODE_VOLUME_UP) "up" else "down", null)
            }
            return true
        }
        return super.dispatchKeyEvent(event)
    }

    override fun onPause() {
        vendorVolumeEnabled = false
        super.onPause()
    }
}
