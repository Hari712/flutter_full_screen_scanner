package com.example.flutter_full_screen_scanner_android

import android.content.Context
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class ScannerPlatformViewFactory(private val plugin: FlutterFullScreenScannerAndroidPlugin) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, id: Int, args: Any?): PlatformView {
        val creationParams = args as? Map<String?, Any?>
        val view = ScannerPlatformView(context, id, creationParams, plugin)
        plugin.activeScannerView = view
        return view
    }
}
