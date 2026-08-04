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

fun mapBarcodeFormat(format: Int): String {
    return when (format) {
        Barcode.FORMAT_CODE_128 -> "org.ansi.Code128"
        Barcode.FORMAT_CODE_39 -> "org.ansi.Code39"
        Barcode.FORMAT_CODE_93 -> "org.ansi.Code93"
        Barcode.FORMAT_CODABAR -> "org.ansi.Codabar"
        Barcode.FORMAT_DATA_MATRIX -> "org.iso.DataMatrix"
        Barcode.FORMAT_EAN_13 -> "org.gs1.EAN-13"
        Barcode.FORMAT_EAN_8 -> "org.gs1.EAN-8"
        Barcode.FORMAT_ITF -> "org.ansi.Interleaved2of5"
        Barcode.FORMAT_QR_CODE -> "org.iso.QRCode"
        Barcode.FORMAT_UPC_A -> "org.gs1.UPC-A"
        Barcode.FORMAT_UPC_E -> "org.gs1.UPC-E"
        Barcode.FORMAT_PDF417 -> "org.iso.PDF417"
        Barcode.FORMAT_AZTEC -> "org.iso.Aztec"
        else -> "unknown"
    }
}

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
                    var rawBitmap: android.graphics.Bitmap? = null
                    var uprightBitmap: android.graphics.Bitmap? = null
                    try {
                        if (barcodes.isNotEmpty()) {
                            android.util.Log.d("BarcodeAnalyzer", "Detected ${barcodes.size} barcodes")
                            val currentTime = System.currentTimeMillis()
                            val validBarcodes = mutableListOf<Map<String, Any?>>()

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

                                // Map points to upright space. ML Kit's cornerPoints are already in the rotated (upright) space.
                                val uprightCorners = cornersList.mapIndexed { idx, point ->
                                    android.util.Log.d("BarcodeAnalyzer", "Corner $idx: raw=(${point.x}, ${point.y}), rotation=$rotation, imgSize=(${imageProxy.width}x${imageProxy.height})")
                                    android.graphics.PointF(point.x.toFloat(), point.y.toFloat())
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
                                            // Ensure all corners are fully inside the scan window to prevent partial/half-visible scans
                                            val allInside = uprightCorners.all { point ->
                                                val px = point.x * scale - dx
                                                val py = point.y * scale - dy
                                                val nx = px / pvWidth
                                                val ny = py / pvHeight
                                                nx >= xMin && nx <= xMax && ny >= yMin && ny <= yMax
                                            }
                                            if (!allInside) {
                                                android.util.Log.d("BarcodeAnalyzer", "Barcode skipped (not inside scan window): $value")
                                                continue // Skip since the barcode is not fully inside the scan window
                                            }
                                        }
                                    }
                                }

                                // Edge bounds check removed to prevent scanning failures on long barcodes

                                val lastScanTime = scannedCache[value]
                                val isNewScan = lastScanTime == null || (currentTime - lastScanTime) >= duplicateDelay

                                if (!allowDuplicate && !isNewScan) {
                                    android.util.Log.d("BarcodeAnalyzer", "Barcode skipped (duplicate): $value")
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
                                                 uprightBitmap.compress(android.graphics.Bitmap.CompressFormat.JPEG, 90, stream)
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
                                        "type" to mapBarcodeFormat(barcode.format),
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
                    } finally {
                        rawBitmap?.recycle()
                        if (uprightBitmap != rawBitmap) {
                            uprightBitmap?.recycle()
                        }
                    }
                }
                .addOnFailureListener {
                    android.util.Log.e("BarcodeAnalyzer", "ML Kit barcode scanning failed", it)
                }
                .addOnCompleteListener {
                    imageProxy.close()
                }
        } catch (e: Exception) {
            imageProxy.close()
        }
    }
}
