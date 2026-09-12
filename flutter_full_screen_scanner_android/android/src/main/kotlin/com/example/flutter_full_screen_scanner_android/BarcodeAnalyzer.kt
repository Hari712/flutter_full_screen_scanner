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
    private val minConfirmations: Int = 2,
    private val scanInterval: Long = 50L,
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
    private val candidateDetections = mutableMapOf<String, MutableList<Long>>()
    private class BlurryState(var count: Int, var lastSeen: Long)
    private val blurryAttempts = mutableMapOf<String, BlurryState>()
    private val compressionExecutor = java.util.concurrent.Executors.newFixedThreadPool(2)
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
        if (currentTime - lastAnalysisTimestamp < scanInterval) {
            imageProxy.close()
            return
        }

        val mediaImage = imageProxy.image
        if (mediaImage == null) {
            imageProxy.close()
            return
        }

        lastAnalysisTimestamp = currentTime

        // AtomicBoolean guard ensures imageProxy.close() fires exactly once across all three listener paths.
        val frameReleased = java.util.concurrent.atomic.AtomicBoolean(false)
        fun releaseFrame() {
            if (frameReleased.compareAndSet(false, true)) imageProxy.close()
        }

        val rotation = imageProxy.imageInfo.rotationDegrees.toFloat()
        val image = InputImage.fromMediaImage(mediaImage, imageProxy.imageInfo.rotationDegrees)
        val scanTask = scanner.process(image)
        scanTask.addOnSuccessListener(executor) { barcodes ->
        var rawBitmap: android.graphics.Bitmap? = null
        var uprightBitmap: android.graphics.Bitmap? = null
        try {
            if (barcodes.isNotEmpty()) {
                android.util.Log.d("BarcodeAnalyzer", "Detected ${barcodes.size} barcodes")
                val currentTime = System.currentTimeMillis()
                val candidates = mutableListOf<ScanData>()

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

                    // 1. Check scan window if set — all four corners must fall within the window
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
                                 val allInside = uprightCorners.all { corner ->
                                     val px = corner.x * scale - dx
                                     val py = corner.y * scale - dy
                                     val nx = px / pvWidth
                                     val ny = py / pvHeight
                                     nx >= xMin && nx <= xMax && ny >= yMin && ny <= yMax
                                 }
                                 if (!allInside) {
                                     continue // Skip since not all corners are inside the scan window
                                 }
                             }
                         }
                    }

                    val lastScanTime = scannedCache[value]
                    val isNewScan = lastScanTime == null || (currentTime - lastScanTime) >= duplicateDelay

                    if (!allowDuplicate && !isNewScan) {
                        continue // Skip duplicate
                    }

                    if (minConfirmations > 1) {
                        val detections = candidateDetections.getOrPut(value) { mutableListOf() }
                        val threshold = currentTime - Math.max(800L, scanInterval * 5L)
                        detections.removeAll { it < threshold }
                        detections.add(currentTime)
                        if (detections.size < minConfirmations) {
                            continue // Skip until we have enough confirmations
                        }
                        candidateDetections.remove(value)
                    }

                    // ML Kit cornerPoints match the upright photo coordinates 1:1
                    val corners = uprightCorners.map { point ->
                        mapOf("x" to point.x.toDouble(), "y" to point.y.toDouble())
                    }

                    candidates.add(ScanData(
                        value = value,
                        format = barcode.format,
                        corners = corners,
                        rawCorners = cornersList.toList(),
                        isNewScan = isNewScan
                    ))
                }

                val scanDataList = mutableListOf<ScanData>()

                if (candidates.isNotEmpty()) {
                    val needsImageCapture = enableImageCapture && candidates.any { it.isNewScan }

                    for (data in candidates) {
                        if (data.isNewScan) {
                            scannedCache[data.value] = currentTime
                        }
                        scanDataList.add(data)
                    }

                    // Decode success is the only quality gate for the barcode value; computeUnionBoundingBox/computeLaplacianVariance are never called unless rejectBlurryImages is true (opt-in photo check only, zero extra CPU at the default).
                    var cropLeft = 0
                    var cropTop = 0
                    if (needsImageCapture) {
                        try {
                            rawBitmap = imageProxy.toBitmap()
                            val rotated = android.graphics.Bitmap.createBitmap(
                                rawBitmap, 0, 0, rawBitmap.width, rawBitmap.height, matrix, true
                            )
                            // Crop to the barcode bounding box before compression to reduce memory and output size.
                            try {
                                val cropRect = computeUnionBoundingBox(scanDataList.filter { it.isNewScan }, rotated.width, rotated.height)
                                if (cropRect != null) {
                                    uprightBitmap = android.graphics.Bitmap.createBitmap(
                                        rotated, cropRect.left, cropRect.top, cropRect.width(), cropRect.height()
                                    )
                                    cropLeft = cropRect.left
                                    cropTop = cropRect.top
                                    rotated.recycle()
                                } else {
                                    uprightBitmap = rotated
                                }
                            } catch (e: Throwable) {
                                uprightBitmap = rotated // fall back to full frame if crop fails
                            }
                        } catch (e: Throwable) {
                            // Ignore fallback
                        }
                    }

                     if (uprightBitmap != null) {
                          val bitmapToCompress = uprightBitmap
                          val outWidth = uprightBitmap.width
                          val outHeight = uprightBitmap.height
                          val capturedCropLeft = cropLeft
                          val capturedCropTop = cropTop

                          try {
                              compressionExecutor.execute {
                                  // Opt-in blur check on the bitmap; gates compression so rejected frames skip that CPU cost too.
                                  var imageRejected = false
                                  var sharpnessScore: Double? = null
                                  if (rejectBlurryImages) {
                                      val newScans = scanDataList.filter { it.isNewScan }
                                      // When cropped, the bitmap IS the barcode region; when full frame, compute the bounding box.
                                      val roi = if (capturedCropLeft != 0 || capturedCropTop != 0) {
                                          android.graphics.Rect(0, 0, outWidth, outHeight)
                                      } else {
                                          computeUnionBoundingBox(newScans, outWidth, outHeight)
                                      }
                                      if (roi != null) {
                                          val variance = computeLaplacianVarianceFromBitmap(bitmapToCompress, roi)
                                          sharpnessScore = variance
                                          if (variance != null && variance < blurThreshold) {
                                              imageRejected = true
                                          }
                                      }
                                  }

                                  var imageBytes: ByteArray? = null
                                  try {
                                      if (!imageRejected) {
                                          val stream = java.io.ByteArrayOutputStream()
                                          bitmapToCompress.compress(android.graphics.Bitmap.CompressFormat.JPEG, 80, stream)
                                          imageBytes = stream.toByteArray()
                                      }
                                  } catch (e: Throwable) {
                                      // Compression error
                                  } finally {
                                      try {
                                          bitmapToCompress.recycle()
                                      } catch (e: Exception) {}
                                  }

                                  val results = scanDataList.map { data ->
                                      val corners = if (capturedCropLeft != 0 || capturedCropTop != 0) {
                                          data.corners.map { c ->
                                              mapOf("x" to ((c["x"] ?: 0.0) - capturedCropLeft), "y" to ((c["y"] ?: 0.0) - capturedCropTop))
                                          }
                                      } else {
                                          data.corners
                                      }
                                      mapOf(
                                          "value" to data.value,
                                          "type" to mapBarcodeFormat(data.format),
                                          "corners" to corners,
                                          "imageWidth" to outWidth,
                                          "imageHeight" to outHeight,
                                          "imageBytes" to if (data.isNewScan && !imageRejected) imageBytes else null,
                                          "timestamp" to currentTime,
                                          "imageRejected" to (data.isNewScan && imageRejected),
                                          "sharpnessScore" to if (data.isNewScan) sharpnessScore else null
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
                                      "imageRejected" to false,
                                      "sharpnessScore" to null
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
                                  "imageRejected" to false,
                                  "sharpnessScore" to null
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
                try { rawBitmap.recycle() } catch (e: Exception) {}
            }
            releaseFrame()
        }
        }
        scanTask.addOnFailureListener { e ->
            android.util.Log.e("BarcodeAnalyzer", "MLKit scanning failed", e)
            releaseFrame()
        }
        scanTask.addOnCanceledListener {
            releaseFrame()
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

    // Same pipeline as computeLaplacianVariance (low-light gate → downsample → box-blur → Laplacian) but reads from a Bitmap so imageProxy need not be open.
    internal fun computeLaplacianVarianceFromBitmap(bitmap: android.graphics.Bitmap, roi: android.graphics.Rect): Double? {
        var roiWidth = roi.width()
        var roiHeight = roi.height()
        if (roiWidth <= 0 || roiHeight <= 0) return null

        val pixelsArgb = IntArray(roiWidth * roiHeight)
        try {
            bitmap.getPixels(pixelsArgb, 0, roiWidth, roi.left, roi.top, roiWidth, roiHeight)
        } catch (e: Exception) {
            return null
        }
        var pixels = IntArray(roiWidth * roiHeight) { i ->
            val p = pixelsArgb[i]
            ((p shr 16 and 0xFF) * 299 + (p shr 8 and 0xFF) * 587 + (p and 0xFF) * 114) / 1000
        }

        var lumaSum = 0L
        for (p in pixels) lumaSum += p
        if (lumaSum.toDouble() / pixels.size < 40.0) return null

        val maxPixelsCeiling = 62500
        while (roiWidth * roiHeight > maxPixelsCeiling && roiWidth >= 4 && roiHeight >= 4) {
            val nw = roiWidth / 2; val nh = roiHeight / 2
            val ds = IntArray(nw * nh)
            for (y in 0 until nh) for (x in 0 until nw) {
                ds[y * nw + x] = (pixels[(y*2)*roiWidth+(x*2)] + pixels[(y*2)*roiWidth+(x*2+1)] +
                    pixels[(y*2+1)*roiWidth+(x*2)] + pixels[(y*2+1)*roiWidth+(x*2+1)]) / 4
            }
            pixels = ds; roiWidth = nw; roiHeight = nh
        }

        val blurred = IntArray(roiWidth * roiHeight)
        for (y in 0 until roiHeight) for (x in 0 until roiWidth) {
            if (y == 0 || y == roiHeight - 1 || x == 0 || x == roiWidth - 1) {
                blurred[y * roiWidth + x] = pixels[y * roiWidth + x]
            } else {
                var sum = 0
                for (ky in -1..1) for (kx in -1..1) sum += pixels[(y+ky)*roiWidth+(x+kx)]
                blurred[y * roiWidth + x] = sum / 9
            }
        }
        pixels = blurred

        var sumL = 0.0; var sumLSq = 0.0; var count = 0
        for (y in 1 until roiHeight - 1) {
            val idx = y * roiWidth
            for (x in 1 until roiWidth - 1) {
                val lap = (pixels[idx-roiWidth+x] + pixels[idx+roiWidth+x] +
                    pixels[idx+x-1] + pixels[idx+x+1] - 4*pixels[idx+x]).toDouble()
                sumL += lap; sumLSq += lap * lap; count++
            }
        }
        if (count == 0) return null
        val mean = sumL / count
        return (sumLSq / count) - (mean * mean)
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

