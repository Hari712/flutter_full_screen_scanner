package com.example.flutter_full_screen_scanner_android

import android.annotation.SuppressLint
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.view.PreviewView
import com.google.mlkit.vision.barcode.BarcodeScanner
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage

class BarcodeAnalyzer(
    private val previewView: PreviewView? = null,
    private val scanWindowWidthFactor: Double? = null,
    private val scanWindowHeightFactor: Double? = null,
    private val enableImageCapture: Boolean = true,
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
        if (mediaImage == null) {
            imageProxy.close()
            return
        }

        try {
            val rotation = imageProxy.imageInfo.rotationDegrees.toFloat()
            val image = InputImage.fromMediaImage(mediaImage, imageProxy.imageInfo.rotationDegrees)
            
            scanner.process(image)
                .addOnSuccessListener { barcodes ->
                    try {
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

                            val imgWidth = rectF.width().toInt()
                            val imgHeight = rectF.height().toInt()

                            for (barcode in barcodes) {
                                val value = barcode.rawValue ?: continue
                                val cornersList = barcode.cornerPoints ?: continue
                                if (cornersList.size < 4) continue

                                // 1. Check if barcode is cut off by the edge of the image sensor frame
                                val padding = 15f
                                val cutOffBySensor = cornersList.any { point ->
                                    point.x < padding || point.x > imgWidth - padding ||
                                    point.y < padding || point.y > imgHeight - padding
                                }
                                if (cutOffBySensor) {
                                    continue // Skip cut off barcode
                                }

                                // 2. Check scan window if set
                                if (scanWindowWidthFactor != null && scanWindowHeightFactor != null) {
                                    val pvWidth = previewView?.width?.toFloat() ?: 0f
                                    val pvHeight = previewView?.height?.toFloat() ?: 0f

                                    if (pvWidth > 0f && pvHeight > 0f) {
                                        val scaleX = pvWidth / imgWidth.toFloat()
                                        val scaleY = pvHeight / imgHeight.toFloat()
                                        val scale = Math.max(scaleX, scaleY)
                                        val dx = (imgWidth.toFloat() * scale - pvWidth) / 2f
                                        val dy = (imgHeight.toFloat() * scale - pvHeight) / 2f

                                        val xMin = 0.5 - scanWindowWidthFactor / 2.0
                                        val xMax = 0.5 + scanWindowWidthFactor / 2.0
                                        val yMin = 0.5 - scanWindowHeightFactor / 2.0
                                        val yMax = 0.5 + scanWindowHeightFactor / 2.0

                                        var allInside = true
                                        for (point in cornersList) {
                                            val px = point.x * scale - dx
                                            val py = point.y * scale - dy
                                            val nx = px / pvWidth
                                            val ny = py / pvHeight

                                            if (nx < xMin || nx > xMax || ny < yMin || ny > yMax) {
                                                allInside = false
                                                break
                                            }
                                        }
                                        if (!allInside) {
                                            continue // Skip since it's not fully inside the scan window
                                        }
                                    }
                                }

                                // 3. Ensure it's not too close to the preview bounds
                                val pvWidth = previewView?.width?.toFloat() ?: 0f
                                val pvHeight = previewView?.height?.toFloat() ?: 0f
                                if (pvWidth > 0f && pvHeight > 0f) {
                                    val scaleX = pvWidth / imgWidth.toFloat()
                                    val scaleY = pvHeight / imgHeight.toFloat()
                                    val scale = Math.max(scaleX, scaleY)
                                    val dx = (imgWidth.toFloat() * scale - pvWidth) / 2f
                                    val dy = (imgHeight.toFloat() * scale - pvHeight) / 2f

                                    val edgeMargin = 0.02f // 2% margin from screen edges
                                    var tooCloseToEdge = false
                                    for (point in cornersList) {
                                        val px = point.x * scale - dx
                                        val py = point.y * scale - dy
                                        val nx = px / pvWidth
                                        val ny = py / pvHeight
                                        if (nx < edgeMargin || nx > 1.0f - edgeMargin || ny < edgeMargin || ny > 1.0f - edgeMargin) {
                                            tooCloseToEdge = true
                                            break
                                        }
                                    }
                                    if (tooCloseToEdge) {
                                        continue
                                    }
                                }

                                val lastScanTime = scannedCache[value]
                                val isNewScan = lastScanTime == null || (currentTime - lastScanTime) >= duplicateDelay

                                if (!allowDuplicate && !isNewScan) {
                                    continue // Skip duplicate
                                }

                                var imageBytes: ByteArray? = null
                                var outWidth = imgWidth
                                var outHeight = imgHeight

                                if (isNewScan) {
                                    scannedCache[value] = currentTime
                                    if (enableImageCapture) {
                                        try {
                                            if (rawBitmap == null) {
                                                rawBitmap = imageProxy.toBitmap()
                                                uprightBitmap = android.graphics.Bitmap.createBitmap(
                                                    rawBitmap, 0, 0, rawBitmap.width, rawBitmap.height, matrix, true
                                                )
                                            }
                                            if (uprightBitmap != null) {
                                                outWidth = uprightBitmap.width
                                                outHeight = uprightBitmap.height
                                                val stream = java.io.ByteArrayOutputStream()
                                                uprightBitmap.compress(android.graphics.Bitmap.CompressFormat.JPEG, 100, stream)
                                                imageBytes = stream.toByteArray()
                                            }
                                        } catch (e: Exception) {
                                            // Fallback if bitmap conversion fails
                                        }
                                    }
                                } else {
                                    if (uprightBitmap != null) {
                                        outWidth = uprightBitmap.width
                                        outHeight = uprightBitmap.height
                                    }
                                }

                                // ML Kit cornerPoints match the upright photo coordinates 1:1
                                val corners = cornersList.map { point ->
                                    mapOf("x" to point.x.toDouble(), "y" to point.y.toDouble())
                                }

                                validBarcodes.add(
                                    mapOf(
                                        "value" to value,
                                        "type" to barcode.format.toString(),
                                        "corners" to corners,
                                        "imageWidth" to outWidth,
                                        "imageHeight" to outHeight,
                                        "imageBytes" to imageBytes,
                                        "timestamp" to currentTime
                                    )
                                )
                            }

                            if (validBarcodes.isNotEmpty()) {
                                onBarcodeDetected(validBarcodes)
                            }
                        }
                    } catch (e: Exception) {
                        // Avoid crashes in success listener
                    }
                }
                .addOnFailureListener {
                    // Optional logging
                }
                .addOnCompleteListener {
                    imageProxy.close()
                }
        } catch (e: Exception) {
            imageProxy.close()
        }
    }
}
