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
    }
    private var cameraProvider: ProcessCameraProvider? = null
    private var camera: Camera? = null
    private var cameraExecutor: ExecutorService
    private var lensFacing = CameraSelector.LENS_FACING_BACK
    private var allowDuplicate: Boolean
    private var duplicateDelay: Long

    init {
        val params = creationParams as? Map<*, *>
        allowDuplicate = params?.get("allowDuplicate") as? Boolean ?: false
        val delayRaw = params?.get("duplicateDelay")
        duplicateDelay = (delayRaw as? Number)?.toLong() ?: 1500L

        cameraExecutor = Executors.newSingleThreadExecutor()
        startCamera()
    }

    override fun getView(): View {
        return previewView
    }

    override fun dispose() {
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

            val preview = Preview.Builder()
                .setResolutionSelector(resolutionSelector)
                .build()
                .also {
                    it.setSurfaceProvider(previewView.surfaceProvider)
                }

            val imageAnalysis = ImageAnalysis.Builder()
                .setResolutionSelector(resolutionSelector)
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .build()
                .also {
                    it.setAnalyzer(cameraExecutor, BarcodeAnalyzer(
                        allowDuplicate = allowDuplicate,
                        duplicateDelay = duplicateDelay,
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

                // Enable continuous focus and exposure for maximum clarity
                val factory = previewView.meteringPointFactory
                val centerPoint = factory.createPoint(0.5f, 0.5f)
                val action = FocusMeteringAction.Builder(centerPoint, FocusMeteringAction.FLAG_AF or FocusMeteringAction.FLAG_AE)
                    .setAutoCancelDuration(3, java.util.concurrent.TimeUnit.SECONDS)
                    .build()
                camera?.cameraControl?.startFocusAndMetering(action)

            } catch(exc: Exception) {
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
