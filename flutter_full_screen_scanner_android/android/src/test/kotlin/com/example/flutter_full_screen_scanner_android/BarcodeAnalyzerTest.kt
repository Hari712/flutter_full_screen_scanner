package com.example.flutter_full_screen_scanner_android

import org.mockito.Mockito
import java.nio.ByteBuffer
import org.junit.Test
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import android.graphics.Rect
import android.graphics.Point
import androidx.camera.core.ImageProxy

@org.junit.runner.RunWith(org.robolectric.RobolectricTestRunner::class)
class BarcodeAnalyzerTest {
    @Test
    fun testComputeUnionBoundingBox() {
        val analyzer = BarcodeAnalyzer(
            executor = Runnable::run,
            onBarcodeDetected = {}
        )
        
        val scan1 = ScanData(
            value = "test1",
            format = 1,
            corners = emptyList(),
            rawCorners = listOf(Point(100, 100), Point(200, 100), Point(200, 200), Point(100, 200)),
            isNewScan = true
        )
        
        val scan2 = ScanData(
            value = "test2",
            format = 1,
            corners = emptyList(),
            rawCorners = listOf(Point(150, 150), Point(250, 150), Point(250, 250), Point(150, 250)),
            isNewScan = true
        )
        
        val rect = analyzer.computeUnionBoundingBox(listOf(scan1, scan2), 1000, 1000)
        assertNotNull(rect)
        // Bounding box range: minX=100, maxX=250, minY=100, maxY=250.
        // Width=150, height=150.
        // padX = 37, padY = 45.
        // minX becomes 63, maxX becomes 287, minY becomes 55, maxY becomes 295.
        assertEquals(63, rect!!.left)
        assertEquals(287, rect.right)
        assertEquals(55, rect.top)
        assertEquals(295, rect.bottom)
    }

    @Test
    fun testComputeLaplacianVariance_sharpVsBlurry() {
        val analyzer = BarcodeAnalyzer(
            executor = Runnable::run,
            onBarcodeDetected = {}
        )

        // Create a 100x100 buffer
        val width = 100
        val height = 100
        val bufferSize = width * height
        val byteBuffer = ByteBuffer.allocate(bufferSize)

        // Checkerboard pattern (sharp edges)
        for (y in 0 until height) {
            for (x in 0 until width) {
                val value = if (((x / 10) + (y / 10)) % 2 == 0) 255 else 0
                byteBuffer.put((value and 0xFF).toByte())
            }
        }

        val plane = Mockito.mock(ImageProxy.PlaneProxy::class.java)
        Mockito.`when`(plane.buffer).thenReturn(byteBuffer)
        Mockito.`when`(plane.rowStride).thenReturn(width)
        Mockito.`when`(plane.pixelStride).thenReturn(1)

        val roi = Rect(10, 10, 90, 90)
        val sharpScore = analyzer.computeLaplacianVariance(plane, roi)
        assertNotNull(sharpScore)

        // Flat/blurry buffer
        val flatBuffer = ByteBuffer.allocate(bufferSize)
        for (i in 0 until bufferSize) {
            flatBuffer.put(128.toByte())
        }
        val blurryPlane = Mockito.mock(ImageProxy.PlaneProxy::class.java)
        Mockito.`when`(blurryPlane.buffer).thenReturn(flatBuffer)
        Mockito.`when`(blurryPlane.rowStride).thenReturn(width)
        Mockito.`when`(blurryPlane.pixelStride).thenReturn(1)

        val blurryScore = analyzer.computeLaplacianVariance(blurryPlane, roi)
        // Blurry score should be very low (0.0 for perfectly flat)
        assertNotNull(blurryScore)
        assertEquals(0.0, blurryScore!!, 0.01)
        
        // Assert sharp is significantly higher than blurry
        assert(sharpScore!! > blurryScore)
    }
}
