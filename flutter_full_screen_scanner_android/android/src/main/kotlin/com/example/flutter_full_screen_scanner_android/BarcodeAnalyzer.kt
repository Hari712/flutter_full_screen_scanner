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

                                // Map points to upright space first using the rotation matrix
                                val uprightCorners = cornersList.map { point ->
                                    val pts = floatArrayOf(point.x.toFloat(), point.y.toFloat())
                                    matrix.mapPoints(pts)
                                    android.graphics.PointF(pts[0], pts[1])
                                }

                                // Cut off sensor check removed to prevent scanning failures on long barcodes

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

                                        if (uprightCorners.isNotEmpty()) {
                                            var sumX = 0f
                                            var sumY = 0f
                                            for (point in uprightCorners) {
                                                sumX += point.x
                                                sumY += point.y
                                            }
                                            val centroidX = sumX / uprightCorners.size
                                            val centroidY = sumY / uprightCorners.size

                                            val px = centroidX * scale - dx
                                            val py = centroidY * scale - dy
                                            val nx = px / pvWidth
                                            val ny = py / pvHeight

                                            if (nx < xMin || nx > xMax || ny < yMin || ny > yMax) {
                                                continue // Skip since the center of the barcode is not inside the scan window
                                            }
                                        }
                                    }
                                }

                                // Edge bounds check removed to prevent scanning failures on long barcodes

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
                                val corners = uprightCorners.map { point ->
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
