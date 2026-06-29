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
            val rotation = imageProxy.imageInfo.rotationDegrees.toFloat()
            val image = InputImage.fromMediaImage(mediaImage, imageProxy.imageInfo.rotationDegrees)
            
            scanner.process(image)
                .addOnSuccessListener { barcodes ->
                    if (barcodes.isNotEmpty()) {
                        val currentTime = System.currentTimeMillis()
                        val validBarcodes = mutableListOf<Map<String, Any?>>()

                        var rawBitmap: android.graphics.Bitmap? = null
                        var uprightBitmap: android.graphics.Bitmap? = null

                        // Matrix to rotate raw sensor bitmap into upright display orientation
                        val matrix = android.graphics.Matrix()
                        matrix.postRotate(rotation)
                        val rectF = android.graphics.RectF(0f, 0f, imageProxy.width.toFloat(), imageProxy.height.toFloat())
                        matrix.mapRect(rectF)
                        matrix.postTranslate(-rectF.left, -rectF.top)

                        for (barcode in barcodes) {
                            val value = barcode.rawValue ?: continue
                            
                            val lastScanTime = scannedCache[value]
                            val isNewScan = lastScanTime == null || (currentTime - lastScanTime) >= duplicateDelay

                            if (!allowDuplicate && !isNewScan) {
                                continue // Skip duplicate
                            }
                            
                            var imageBytes: ByteArray? = null
                            var imgWidth = rectF.width().toInt()
                            var imgHeight = rectF.height().toInt()

                            if (isNewScan) {
                                scannedCache[value] = currentTime
                                try {
                                    if (rawBitmap == null) {
                                        rawBitmap = imageProxy.toBitmap()
                                        uprightBitmap = android.graphics.Bitmap.createBitmap(
                                            rawBitmap, 0, 0, rawBitmap.width, rawBitmap.height, matrix, true
                                        )
                                    }
                                    if (uprightBitmap != null) {
                                        imgWidth = uprightBitmap.width
                                        imgHeight = uprightBitmap.height
                                        val stream = java.io.ByteArrayOutputStream()
                                        uprightBitmap.compress(android.graphics.Bitmap.CompressFormat.JPEG, 100, stream)
                                        imageBytes = stream.toByteArray()
                                    }
                                } catch (e: Exception) {
                                    // Fallback if bitmap conversion fails
                                }
                            } else {
                                if (uprightBitmap != null) {
                                    imgWidth = uprightBitmap.width
                                    imgHeight = uprightBitmap.height
                                }
                            }

                            // ML Kit cornerPoints match the upright photo coordinates 1:1
                            val corners = barcode.cornerPoints?.map { point ->
                                mapOf("x" to point.x.toDouble(), "y" to point.y.toDouble())
                            }

                            validBarcodes.add(
                                mapOf(
                                    "value" to value,
                                    "type" to barcode.format.toString(),
                                    "corners" to corners,
                                    "imageWidth" to imgWidth,
                                    "imageHeight" to imgHeight,
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
                    // Optional logging
                }
                .addOnCompleteListener {
                    imageProxy.close()
                }
        } else {
            imageProxy.close()
        }
    }
}
