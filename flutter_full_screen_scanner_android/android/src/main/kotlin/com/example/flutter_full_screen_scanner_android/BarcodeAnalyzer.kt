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

import com.google.android.gms.tasks.Tasks

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

fun mapStringToFormat(formatStr: String): Int? {
    return when (formatStr.lowercase()) {
        "code128" -> Barcode.FORMAT_CODE_128
        "code39" -> Barcode.FORMAT_CODE_39
        "code93" -> Barcode.FORMAT_CODE_93
        "codabar" -> Barcode.FORMAT_CODABAR
        "datamatrix" -> Barcode.FORMAT_DATA_MATRIX
        "ean13" -> Barcode.FORMAT_EAN_13
        "ean8" -> Barcode.FORMAT_EAN_8
        "itf" -> Barcode.FORMAT_ITF
        "qrcode" -> Barcode.FORMAT_QR_CODE
        "upca" -> Barcode.FORMAT_UPC_A
        "upce" -> Barcode.FORMAT_UPC_E
        "pdf417" -> Barcode.FORMAT_PDF417
        "aztec" -> Barcode.FORMAT_AZTEC
        else -> null
    }
}

internal data class ScanData(
    val value: String,
    val format: Int,
    val corners: List<Map<String, Double>>,
    val rawCorners: List<android.graphics.Point>,
    val isNewScan: Boolean
)

class BarcodeAnalyzer(
    private val previewView: PreviewView? = null,
    private val scanWindowWidthFactor: Double? = null,
    private val scanWindowHeightFactor: Double? = null,
    private val enableImageCapture: Boolean = true,
    private val allowDuplicate: Boolean = false,
    private val duplicateDelay: Long = 1500L,
    private val supportedFormats: List<String>? = null,
    private val rejectBlurryImages: Boolean = false,
    private val blurThreshold: Double = 35.0,
    private val executor: java.util.concurrent.Executor,
    private val onBarcodeDetected: (List<Map<String, Any?>>) -> Unit
) : ImageAnalysis.Analyzer {

    private val scanner: BarcodeScanner by lazy {
        val builder = BarcodeScannerOptions.Builder()
        val mlFormats = supportedFormats?.mapNotNull { mapStringToFormat(it) }
        if (mlFormats != null && mlFormats.isNotEmpty()) {
            if (mlFormats.size == 1) {
                builder.setBarcodeFormats(mlFormats.first())
            } else {
                builder.setBarcodeFormats(mlFormats.first(), *mlFormats.drop(1).toIntArray())
            }
        } else {
            builder.setBarcodeFormats(Barcode.FORMAT_ALL_FORMATS)
        }
        BarcodeScanning.getClient(builder.build())
    }
    private val scannedCache = mutableMapOf<String, Long>()
    private val compressionExecutor = java.util.concurrent.Executors.newCachedThreadPool()
    private var lastAnalysisTimestamp = 0L

    fun close() {
        try {
            scanner.close()
        } catch (e: Exception) {
            // Ignored
        }
        try {
            compressionExecutor.shutdown()
        } catch (e: Exception) {
            // Ignored
        }
    }

    @SuppressLint("UnsafeOptInUsageError")
    override fun analyze(imageProxy: ImageProxy) {
        val currentTime = System.currentTimeMillis()
        if (currentTime - lastAnalysisTimestamp < 150) { // Limit to ~6.6 scans per second
            imageProxy.close()
            return
        }

        val mediaImage = imageProxy.image
        if (mediaImage == null) {
            imageProxy.close()
            return
        }

        lastAnalysisTimestamp = currentTime

        var rawBitmap: android.graphics.Bitmap? = null
        var uprightBitmap: android.graphics.Bitmap? = null
        try {
            val rotation = imageProxy.imageInfo.rotationDegrees.toFloat()
            val image = InputImage.fromMediaImage(mediaImage, imageProxy.imageInfo.rotationDegrees)
            
            // Perform synchronous scanning to leverage CameraX's KEEP_ONLY_LATEST strategy.
            // This prevents frame processing backlog and avoids camera buffer/preview starvation.
            val barcodes = Tasks.await(scanner.process(image))

            if (barcodes.isNotEmpty()) {
                android.util.Log.d("BarcodeAnalyzer", "Detected ${barcodes.size} barcodes")
                val currentTime = System.currentTimeMillis()
                val scanDataList = mutableListOf<ScanData>()

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

                     // ML Kit corner points are already in the upright display-oriented space.
                     val uprightCorners = cornersList.map { point ->
                         android.graphics.PointF(point.x.toFloat(), point.y.toFloat())
                     }

                    // 1. Check scan window if set using centroid (center point) to match Dart-side calculation
                    if (scanWindowWidthFactor != null && scanWindowHeightFactor != null) {
                        val pvWidth = previewView?.width?.toFloat() ?: 0f
                        val pvHeight = previewView?.height?.toFloat() ?: 0f

                         if (pvWidth > 0f && pvHeight > 0f) {
                             val scaleX = pvWidth / imgWidth.toFloat()
                             val scaleY = pvHeight / imgHeight.toFloat()
                             val scale = Math.max(scaleX, scaleY)
                             val dx = (imgWidth.toFloat() * scale - pvWidth) / 2f
                             val dy = (imgHeight.toFloat() * scale - pvHeight) / 2f

                             val wFactor = if (scanWindowWidthFactor.isInfinite() || scanWindowWidthFactor.isNaN()) 1.0 else scanWindowWidthFactor.coerceIn(0.0, 1.0)
                             val hFactor = if (scanWindowHeightFactor.isInfinite() || scanWindowHeightFactor.isNaN()) 1.0 else scanWindowHeightFactor.coerceIn(0.0, 1.0)
                             val xMin = 0.5 - wFactor / 2.0
                             val xMax = 0.5 + wFactor / 2.0
                             val yMin = 0.5 - hFactor / 2.0
                             val yMax = 0.5 + hFactor / 2.0

                             if (uprightCorners.isNotEmpty()) {
                                 val sumX = uprightCorners.map { it.x }.sum()
                                 val sumY = uprightCorners.map { it.y }.sum()
                                 val cx = sumX / uprightCorners.size
                                 val cy = sumY / uprightCorners.size
                                 
                                 val px = cx * scale - dx
                                 val py = cy * scale - dy
                                 val nx = px / pvWidth
                                 val ny = py / pvHeight
                                 
                                 val inside = nx >= xMin && nx <= xMax && ny >= yMin && ny <= yMax
                                 android.util.Log.d("BarcodeAnalyzer", "ScanWindow check: value=$value, cx=$cx, cy=$cy, nx=$nx, ny=$ny, xRange=[$xMin, $xMax], yRange=[$yMin, $yMax], inside=$inside")
                                 if (!inside) {
                                     continue // Skip since the barcode is not inside the scan window
                                 }
                             }
                         }
                    }

                    val lastScanTime = scannedCache[value]
                    val isNewScan = lastScanTime == null || (currentTime - lastScanTime) >= duplicateDelay

                    if (!allowDuplicate && !isNewScan) {
                        continue // Skip duplicate
                    }

                    if (isNewScan) {
                        scannedCache[value] = currentTime
                    }

                    // ML Kit cornerPoints match the upright photo coordinates 1:1
                    val corners = uprightCorners.map { point ->
                        mapOf("x" to point.x.toDouble(), "y" to point.y.toDouble())
                    }

                    scanDataList.add(ScanData(
                        value = value,
                        format = barcode.format,
                        corners = corners,
                        rawCorners = cornersList.toList(),
                        isNewScan = isNewScan
                    ))
                }

                if (scanDataList.isNotEmpty()) {
                    val needsImageCapture = enableImageCapture && scanDataList.any { it.isNewScan }
                    var sharpness: Double? = null
                    var isBlurry = false

                    if (needsImageCapture && rejectBlurryImages) {
                        try {
                            val mediaImage = imageProxy.image
                            if (mediaImage != null && mediaImage.format == android.graphics.ImageFormat.YUV_420_888) {
                                val newScans = scanDataList.filter { it.isNewScan }
                                val roi = computeUnionBoundingBox(newScans, imageProxy.width, imageProxy.height)
                                if (roi != null) {
                                    val roiArea = (roi.width() * roi.height()).toDouble()
                                    val totalArea = (imageProxy.width * imageProxy.height).toDouble()
                                    if (roiArea > 0 && roiArea / totalArea <= 0.8) {
                                        sharpness = computeLaplacianVariance(imageProxy.planes[0], roi)
                                        if (sharpness != null) {
                                            isBlurry = sharpness < blurThreshold
                                        }
                                    } else {
                                        android.util.Log.d("BarcodeAnalyzer", "ROI area ratio ${roiArea/totalArea} exceeds 80%, skipping blur check")
                                    }
                                }
                            }
                        } catch (e: Throwable) {
                            android.util.Log.e("BarcodeAnalyzer", "Error computing blur score", e)
                        }
                    }

                    val actualCapture = needsImageCapture && !isBlurry

                    if (actualCapture) {
                        try {
                            rawBitmap = imageProxy.toBitmap()
                            uprightBitmap = android.graphics.Bitmap.createBitmap(
                                rawBitmap, 0, 0, rawBitmap.width, rawBitmap.height, matrix, true
                            )
                        } catch (e: Throwable) {
                            // Ignore fallback
                        }
                    }

                     if (uprightBitmap != null) {
                         val bitmapToCompress = uprightBitmap
                         val outWidth = uprightBitmap.width
                         val outHeight = uprightBitmap.height

                         try {
                             compressionExecutor.execute {
                                 var imageBytes: ByteArray? = null
                                 try {
                                     val stream = java.io.ByteArrayOutputStream()
                                     bitmapToCompress.compress(android.graphics.Bitmap.CompressFormat.JPEG, 80, stream)
                                     imageBytes = stream.toByteArray()
                                 } catch (e: Throwable) {
                                     // Compression error
                                 } finally {
                                     try {
                                         bitmapToCompress.recycle()
                                     } catch (e: Exception) {}
                                 }

                                 val results = scanDataList.map { data ->
                                     mapOf(
                                         "value" to data.value,
                                         "type" to mapBarcodeFormat(data.format),
                                         "corners" to data.corners,
                                         "imageWidth" to outWidth,
                                         "imageHeight" to outHeight,
                                         "imageBytes" to if (data.isNewScan) imageBytes else null,
                                         "timestamp" to currentTime,
                                         "imageRejected" to (data.isNewScan && isBlurry),
                                         "sharpnessScore" to sharpness
                                     )
                                 }
                                 onBarcodeDetected(results)
                             }
                         } catch (e: java.util.concurrent.RejectedExecutionException) {
                             try {
                                 bitmapToCompress.recycle()
                             } catch (ex: Exception) {}
                             val results = scanDataList.map { data ->
                                 mapOf(
                                     "value" to data.value,
                                     "type" to mapBarcodeFormat(data.format),
                                     "corners" to data.corners,
                                     "imageWidth" to outWidth,
                                     "imageHeight" to outHeight,
                                     "imageBytes" to null,
                                     "timestamp" to currentTime,
                                     "imageRejected" to (data.isNewScan && isBlurry),
                                     "sharpnessScore" to sharpness
                                 )
                             }
                             onBarcodeDetected(results)
                         }
                     } else {
                         val results = scanDataList.map { data ->
                             mapOf(
                                 "value" to data.value,
                                 "type" to mapBarcodeFormat(data.format),
                                 "corners" to data.corners,
                                 "imageWidth" to imgWidth,
                                 "imageHeight" to imgHeight,
                                 "imageBytes" to null,
                                 "timestamp" to currentTime,
                                 "imageRejected" to (data.isNewScan && isBlurry),
                                 "sharpnessScore" to sharpness
                             )
                         }
                         onBarcodeDetected(results)
                     }
                }
            }
        } catch (e: Throwable) {
            android.util.Log.e("BarcodeAnalyzer", "Error processing image frame", e)
        } finally {
            if (rawBitmap != null && rawBitmap != uprightBitmap) {
                try {
                    rawBitmap.recycle()
                } catch (e: Exception) {}
            }
            imageProxy.close()
        }
    }

    internal fun computeUnionBoundingBox(newScans: List<ScanData>, imgWidth: Int, imgHeight: Int): android.graphics.Rect? {
        if (newScans.isEmpty()) return null
        var minX = imgWidth
        var maxX = 0
        var minY = imgHeight
        var maxY = 0
        var hasPoints = false

        for (scan in newScans) {
            for (pt in scan.rawCorners) {
                if (pt.x < minX) minX = pt.x
                if (pt.x > maxX) maxX = pt.x
                if (pt.y < minY) minY = pt.y
                if (pt.y > maxY) maxY = pt.y
                hasPoints = true
            }
        }
        if (!hasPoints) return null

        // Add 10% padding
        val width = maxX - minX
        val height = maxY - minY
        val padX = (width * 0.10f).toInt().coerceAtLeast(10)
        val padY = (height * 0.10f).toInt().coerceAtLeast(10)

        minX = (minX - padX).coerceIn(0, imgWidth - 1)
        maxX = (maxX + padX).coerceIn(0, imgWidth - 1)
        minY = (minY - padY).coerceIn(0, imgHeight - 1)
        maxY = (maxY + padY).coerceIn(0, imgHeight - 1)

        if (maxX - minX < 20 || maxY - minY < 20) {
            // Under minimum size floor (20x20 = 400px)
            return null
        }

        return android.graphics.Rect(minX, minY, maxX, maxY)
    }

    internal fun computeLaplacianVariance(
        yPlane: androidx.camera.core.ImageProxy.PlaneProxy,
        roi: android.graphics.Rect
    ): Double? {
        val buffer = yPlane.buffer
        val rowStride = yPlane.rowStride
        val pixelStride = yPlane.pixelStride

        var roiWidth = roi.width()
        var roiHeight = roi.height()

        // 1. Extract the ROI pixel data into a flat Yuv/Luma byte array (or IntArray)
        var pixels = IntArray(roiWidth * roiHeight)
        buffer.position(0)
        for (y in 0 until roiHeight) {
            val rowStart = (roi.top + y) * rowStride
            for (x in 0 until roiWidth) {
                val offset = rowStart + (roi.left + x) * pixelStride
                if (offset < buffer.capacity()) {
                    pixels[y * roiWidth + x] = buffer.get(offset).toInt() and 0xFF
                } else {
                    pixels[y * roiWidth + x] = 0
                }
            }
        }

        // 2. Low Light / Sensor Noise Mitigation: compute mean luma first
        var lumaSum = 0L
        for (p in pixels) {
            lumaSum += p
        }
        val meanLuma = lumaSum.toDouble() / pixels.size
        if (meanLuma < 40.0) {
            android.util.Log.d("BarcodeAnalyzer", "Low light detected (mean luma: $meanLuma < 40.0), skipping blur rejection")
            return null
        }

        // 3. Max ROI Downsampling cap
        val maxPixelsCeiling = 62500
        while (roiWidth * roiHeight > maxPixelsCeiling && roiWidth >= 4 && roiHeight >= 4) {
            val newWidth = roiWidth / 2
            val newHeight = roiHeight / 2
            val downsampled = IntArray(newWidth * newHeight)
            for (y in 0 until newHeight) {
                for (x in 0 until newWidth) {
                    val p00 = pixels[(y * 2) * roiWidth + (x * 2)]
                    val p01 = pixels[(y * 2) * roiWidth + (x * 2 + 1)]
                    val p10 = pixels[(y * 2 + 1) * roiWidth + (x * 2)]
                    val p11 = pixels[(y * 2 + 1) * roiWidth + (x * 2 + 1)]
                    downsampled[y * newWidth + x] = (p00 + p01 + p10 + p11) / 4
                }
            }
            pixels = downsampled
            roiWidth = newWidth
            roiHeight = newHeight
        }

        // 4. Cheap 3x3 box blur (noise pre-pass)
        val blurredPixels = IntArray(roiWidth * roiHeight)
        for (y in 0 until roiHeight) {
            for (x in 0 until roiWidth) {
                if (y == 0 || y == roiHeight - 1 || x == 0 || x == roiWidth - 1) {
                    blurredPixels[y * roiWidth + x] = pixels[y * roiWidth + x]
                } else {
                    var sum = 0
                    for (ky in -1..1) {
                        for (kx in -1..1) {
                            sum += pixels[(y + ky) * roiWidth + (x + kx)]
                        }
                    }
                    blurredPixels[y * roiWidth + x] = sum / 9
                }
            }
        }
        pixels = blurredPixels

        // 5. Laplacian kernel [[0, 1, 0], [1, -4, 1], [0, 1, 0]]
        var sumLaplacian = 0.0
        var sumLaplacianSq = 0.0
        var count = 0

        for (y in 1 until roiHeight - 1) {
            val idx = y * roiWidth
            for (x in 1 until roiWidth - 1) {
                val center = pixels[idx + x]
                val left = pixels[idx + x - 1]
                val right = pixels[idx + x + 1]
                val up = pixels[idx - roiWidth + x]
                val down = pixels[idx + roiWidth + x]

                // Laplacian response
                val lap = (up + down + left + right - 4 * center).toDouble()
                sumLaplacian += lap
                sumLaplacianSq += lap * lap
                count++
            }
        }

        if (count == 0) return null

        val mean = sumLaplacian / count
        val variance = (sumLaplacianSq / count) - (mean * mean)
        return variance
    }
}

class SafeExecutor(private val delegate: java.util.concurrent.Executor) : java.util.concurrent.Executor {
    override fun execute(command: Runnable) {
        try {
            delegate.execute(command)
        } catch (e: java.util.concurrent.RejectedExecutionException) {
            // Ignored: The executor has been shut down, so we discard any pending callbacks.
        }
    }
}

