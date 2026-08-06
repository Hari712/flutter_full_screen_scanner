package com.example.flutter_full_screen_scanner_android

import android.content.Context
import android.view.View
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import io.flutter.plugin.platform.PlatformView
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class ScannerPlatformView(
    private val context: Context,
    id: Int,
    creationParams: Map<String?, Any?>?,
    private val plugin: FlutterFullScreenScannerAndroidPlugin
) : PlatformView {

    private val previewView: PreviewView = PreviewView(context).apply {
        implementationMode = PreviewView.ImplementationMode.COMPATIBLE
        scaleType = PreviewView.ScaleType.FILL_CENTER
    }
    private var cameraProvider: ProcessCameraProvider? = null
    private var camera: Camera? = null
    private var cameraExecutor: ExecutorService
    private var lensFacing = CameraSelector.LENS_FACING_BACK
    private var allowDuplicate: Boolean
    private var duplicateDelay: Long
    private var enableImageCapture: Boolean = true
    private var scanWindowWidthFactor: Double? = null
    private var scanWindowHeightFactor: Double? = null
    private var supportedFormats: List<String>? = null
    private var displayListener: android.hardware.display.DisplayManager.DisplayListener? = null

    init {
        val params = creationParams as? Map<*, *>
        allowDuplicate = params?.get("allowDuplicate") as? Boolean ?: false
        val delayRaw = params?.get("duplicateDelay")
        duplicateDelay = (delayRaw as? Number)?.toLong() ?: 1500L
        enableImageCapture = params?.get("enableImageCapture") as? Boolean ?: true
        scanWindowWidthFactor = params?.get("scanWindowWidthFactor") as? Double
        scanWindowHeightFactor = params?.get("scanWindowHeightFactor") as? Double
        supportedFormats = (params?.get("supportedFormats") as? List<*>)?.mapNotNull { it as? String }

        cameraExecutor = Executors.newSingleThreadExecutor()
        startCamera()
    }

    override fun getView(): View {
        return previewView
    }

    override fun dispose() {
        displayListener?.let {
            val displayManager = context.getSystemService(Context.DISPLAY_SERVICE) as? android.hardware.display.DisplayManager
            displayManager?.unregisterDisplayListener(it)
        }
        displayListener = null

        try {
            cameraProvider?.unbindAll()
        } catch (e: Exception) {
            // Ignored
        }
        cameraProvider = null
        camera = null
        if (!cameraExecutor.isShutdown) {
            cameraExecutor.shutdownNow()
        }
    }

    private fun startCamera() {
        val cameraProviderFuture = ProcessCameraProvider.getInstance(context)

        cameraProviderFuture.addListener({
            cameraProvider = cameraProviderFuture.get()

            val resolutionSelector = androidx.camera.core.resolutionselector.ResolutionSelector.Builder()
                .setAspectRatioStrategy(androidx.camera.core.resolutionselector.AspectRatioStrategy.RATIO_16_9_FALLBACK_AUTO_STRATEGY)
                .setResolutionStrategy(androidx.camera.core.resolutionselector.ResolutionStrategy(
                    android.util.Size(1920, 1080),
                    androidx.camera.core.resolutionselector.ResolutionStrategy.FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER
                ))
                .build()

            val displayManager = context.getSystemService(Context.DISPLAY_SERVICE) as android.hardware.display.DisplayManager
            val display = try {
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
                    context.display
                } else {
                    null
                }
            } catch (e: Exception) {
                null
            } ?: (context.getSystemService(Context.WINDOW_SERVICE) as android.view.WindowManager).defaultDisplay
            val initialRotation = display?.rotation ?: android.view.Surface.ROTATION_0

            val preview = Preview.Builder()
                .setResolutionSelector(resolutionSelector)
                .build()
                .also {
                    it.setSurfaceProvider(previewView.surfaceProvider)
                }

            val imageAnalysis = ImageAnalysis.Builder()
                .setResolutionSelector(resolutionSelector)
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .setTargetRotation(initialRotation)
                .build()
                .also {
                    it.setAnalyzer(cameraExecutor, BarcodeAnalyzer(
                        previewView = previewView,
                        scanWindowWidthFactor = scanWindowWidthFactor,
                        scanWindowHeightFactor = scanWindowHeightFactor,
                        enableImageCapture = enableImageCapture,
                        allowDuplicate = allowDuplicate,
                        duplicateDelay = duplicateDelay,
                        supportedFormats = supportedFormats,
                        executor = cameraExecutor,
                        onBarcodeDetected = { results ->
                            ContextCompat.getMainExecutor(context).execute {
                                plugin.eventSink?.success(
                                    mapOf(
                                        "type" to "scanned",
                                        "data" to results
                                    )
                                )
                            }
                        }
                    ))
                }

            displayListener?.let { displayManager.unregisterDisplayListener(it) }
            displayListener = object : android.hardware.display.DisplayManager.DisplayListener {
                override fun onDisplayAdded(displayId: Int) {}
                override fun onDisplayRemoved(displayId: Int) {}
                override fun onDisplayChanged(displayId: Int) {
                    val currentRotation = display?.rotation ?: android.view.Surface.ROTATION_0
                    try {
                        imageAnalysis.targetRotation = currentRotation
                    } catch (e: Exception) {
                        // Ignored
                    }
                }
            }
            displayManager.registerDisplayListener(displayListener, android.os.Handler(android.os.Looper.getMainLooper()))

            val cameraSelector = CameraSelector.Builder()
                .requireLensFacing(lensFacing)
                .build()

            try {
                cameraProvider?.unbindAll()

                val lifecycleOwner = plugin.lifecycleOwner ?: return@addListener

                camera = cameraProvider?.bindToLifecycle(
                    lifecycleOwner,
                    cameraSelector,
                    preview,
                    imageAnalysis
                )

                val zoomState = camera?.cameraInfo?.zoomState?.value
                if (zoomState != null) {
                    val maxZoom = zoomState.maxZoomRatio
                    val minZoom = zoomState.minZoomRatio
                    val targetZoom = 1.0f.coerceIn(minZoom, maxZoom)
                    camera?.cameraControl?.setZoomRatio(targetZoom)
                } else {
                    camera?.cameraControl?.setZoomRatio(1.0f)
                }            } catch(exc: Exception) {
                // Log exception
            }

        }, ContextCompat.getMainExecutor(context))
    }

    fun pause() {
        cameraProvider?.unbindAll()
    }

    fun resume() {
        startCamera()
    }

    fun stop() {
        cameraProvider?.unbindAll()
    }

    fun toggleFlash(): Boolean {
        val currentTorch = camera?.cameraInfo?.torchState?.value ?: TorchState.OFF
        val newTorchState = currentTorch == TorchState.OFF
        camera?.cameraControl?.enableTorch(newTorchState)
        return newTorchState
    }

    fun switchCamera() {
        lensFacing = if (lensFacing == CameraSelector.LENS_FACING_BACK) {
            CameraSelector.LENS_FACING_FRONT
        } else {
            CameraSelector.LENS_FACING_BACK
        }
        startCamera()
    }

    fun focusAt(x: Double, y: Double) {
        val factory = previewView.meteringPointFactory
        val point = factory.createPoint(x.toFloat(), y.toFloat())
        val action = FocusMeteringAction.Builder(point).build()
        camera?.cameraControl?.startFocusAndMetering(action)
    }
}
