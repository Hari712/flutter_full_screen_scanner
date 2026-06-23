package com.example.flutter_full_screen_scanner_android

import android.annotation.SuppressLint
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import com.google.mlkit.vision.barcode.BarcodeScanner
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage

class BarcodeAnalyzer(
    private val allowDuplicate: Boolean = false,
    private val duplicateDelay: Long = 1500L,
    private val onBarcodeDetected: (List<Map<String, Any?>>) -> Unit
) : ImageAnalysis.Analyzer {

    private val scanner: BarcodeScanner
    private val scannedCache = mutableMapOf<String, Long>()

    init {
        val options = BarcodeScannerOptions.Builder()
            .setBarcodeFormats(Barcode.FORMAT_ALL_FORMATS)
            .build()
        scanner = BarcodeScanning.getClient(options)
    }

    @SuppressLint("UnsafeOptInUsageError")
    override fun analyze(imageProxy: ImageProxy) {
        val mediaImage = imageProxy.image
        if (mediaImage != null) {
            val image = InputImage.fromMediaImage(mediaImage, imageProxy.imageInfo.rotationDegrees)
            scanner.process(image)
                .addOnSuccessListener { barcodes ->
                    if (barcodes.isNotEmpty()) {
                        val currentTime = System.currentTimeMillis()
                        val validBarcodes = mutableListOf<Map<String, Any?>>()

                        for (barcode in barcodes) {
                            val value = barcode.rawValue ?: continue
                            
                            if (!allowDuplicate) {
                                val lastScanTime = scannedCache[value]
                                if (lastScanTime != null && (currentTime - lastScanTime) < duplicateDelay) {
                                    continue // Skip duplicate
                                }
                            }
                            
                            scannedCache[value] = currentTime

                            val rawBitmap = imageProxy.toBitmap()
                            val matrix = android.graphics.Matrix()
                            matrix.postRotate(imageProxy.imageInfo.rotationDegrees.toFloat())
                            val bitmap = android.graphics.Bitmap.createBitmap(rawBitmap, 0, 0, rawBitmap.width, rawBitmap.height, matrix, true)
                            
                            val corners = barcode.cornerPoints?.map { point ->
                                val pts = floatArrayOf(point.x.toFloat(), point.y.toFloat())
                                matrix.mapPoints(pts)
                                mapOf("x" to pts[0].toDouble(), "y" to pts[1].toDouble())
                            }

                            val stream = java.io.ByteArrayOutputStream()
                            bitmap.compress(android.graphics.Bitmap.CompressFormat.JPEG, 100, stream)
                            val imageBytes = stream.toByteArray()

                            validBarcodes.add(
                                mapOf(
                                    "value" to value,
                                    "type" to barcode.format.toString(),
                                    "corners" to corners,
                                    "imageWidth" to bitmap.width,
                                    "imageHeight" to bitmap.height,
                                    "imageBytes" to imageBytes,
                                    "timestamp" to currentTime
                                )
                            )
                        }

                        if (validBarcodes.isNotEmpty()) {
                            onBarcodeDetected(validBarcodes)
                        }
                    }
                }
                .addOnFailureListener {
                    // Optional: log error or send EventChannel error
                }
                .addOnCompleteListener {
                    imageProxy.close()
                }
        } else {
            imageProxy.close()
        }
    }
}
