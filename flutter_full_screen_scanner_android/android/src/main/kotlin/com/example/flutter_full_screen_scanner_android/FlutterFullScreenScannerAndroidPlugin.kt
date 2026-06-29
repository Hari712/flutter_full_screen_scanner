package com.example.flutter_full_screen_scanner_android

import android.Manifest
import android.content.pm.PackageManager
import android.net.Uri
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.embedding.engine.plugins.lifecycle.HiddenLifecycleReference
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.PluginRegistry
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage
import java.io.File

/** FlutterFullScreenScannerAndroidPlugin */
class FlutterFullScreenScannerAndroidPlugin : FlutterPlugin, ActivityAware, ScannerHostApi, EventChannel.StreamHandler, PluginRegistry.RequestPermissionsResultListener {

    var activeScannerView: ScannerPlatformView? = null
    var lifecycleOwner: LifecycleOwner? = null
    var eventSink: EventChannel.EventSink? = null
    private var eventChannel: EventChannel? = null
    private var activityBinding: ActivityPluginBinding? = null

    companion object {
        private const val CAMERA_PERMISSION_REQUEST_CODE = 1987
    }

    fun checkAndRequestCameraPermission(): Boolean {
        val activity = activityBinding?.activity ?: return false
        if (ContextCompat.checkSelfPermission(activity, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
            return true
        }
        ActivityCompat.requestPermissions(activity, arrayOf(Manifest.permission.CAMERA), CAMERA_PERMISSION_REQUEST_CODE)
        return false
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray): Boolean {
        if (requestCode == CAMERA_PERMISSION_REQUEST_CODE) {
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                activeScannerView?.resume()
            }
            return true
        }
        return false
    }

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        ScannerHostApi.setUp(flutterPluginBinding.binaryMessenger, this)

        eventChannel = EventChannel(flutterPluginBinding.binaryMessenger, "flutter_full_screen_scanner_events")
        eventChannel?.setStreamHandler(this)

        flutterPluginBinding.platformViewRegistry.registerViewFactory(
            "flutter_full_screen_scanner_view",
            ScannerPlatformViewFactory(this)
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        ScannerHostApi.setUp(binding.binaryMessenger, null)
        eventChannel?.setStreamHandler(null)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
        updateLifecycleOwner(binding)
        checkAndRequestCameraPermission()
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        lifecycleOwner = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
        updateLifecycleOwner(binding)
    }

    override fun onDetachedFromActivity() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        lifecycleOwner = null
    }

    private fun updateLifecycleOwner(binding: ActivityPluginBinding) {
        val activity = binding.activity
        if (activity is LifecycleOwner) {
            lifecycleOwner = activity
        } else {
            val reference = binding.lifecycle as? HiddenLifecycleReference
            if (reference != null) {
                lifecycleOwner = object : LifecycleOwner {
                    override val lifecycle: androidx.lifecycle.Lifecycle
                        get() = reference.lifecycle
                }
            }
        }
    }

    // --- ScannerHostApi Implementation ---

    override fun pause() {
        activeScannerView?.pause()
    }

    override fun resume() {
        activeScannerView?.resume()
    }

    override fun stop() {
        activeScannerView?.stop()
    }

    override fun toggleFlash(): Boolean {
        return activeScannerView?.toggleFlash() ?: false
    }

    override fun switchCamera() {
        activeScannerView?.switchCamera()
    }

    override fun focusAt(x: Double, y: Double) {
        activeScannerView?.focusAt(x, y)
    }

    override fun scanImage(path: String, callback: (Result<List<ScannerResultData?>>) -> Unit) {
        val context = activeScannerView?.getView()?.context
        if (context == null) {
            callback(Result.failure(Exception("Scanner view context is null")))
            return
        }

        try {
            val uri = Uri.fromFile(File(path))
            val image = InputImage.fromFilePath(context, uri)
            
            val options = BarcodeScannerOptions.Builder()
                .setBarcodeFormats(Barcode.FORMAT_ALL_FORMATS)
                .build()
            val scanner = BarcodeScanning.getClient(options)

            scanner.process(image)
                .addOnSuccessListener { barcodes ->
                    val results = barcodes.map { barcode ->
                        val corners = barcode.cornerPoints?.map { point ->
                            PointData(point.x.toDouble(), point.y.toDouble())
                        }
                        ScannerResultData(
                            value = barcode.rawValue,
                            type = barcode.format.toString(),
                            corners = corners,
                            imageWidth = image.width.toLong(),
                            imageHeight = image.height.toLong(),
                            timestamp = System.currentTimeMillis()
                        )
                    }
                    callback(Result.success(results))
                }
                .addOnFailureListener { e ->
                    callback(Result.failure(e))
                }
        } catch (e: Exception) {
            callback(Result.failure(e))
        }
    }

    override fun dispose() {
        activeScannerView?.dispose()
        activeScannerView = null
    }
}
