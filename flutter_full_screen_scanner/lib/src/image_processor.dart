import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'scanner_models.dart';

/// Handles background image processing tasks such as drawing annotations.
class ImageProcessor {
  /// Annotates the given image bytes with a bounding box around the detected barcode.
  /// This operation is computationally heavy and runs in a background isolate
  /// to prevent dropping frames on the main UI thread.
  static Future<Uint8List?> annotateImage(
    Uint8List imageBytes,
    List<Point> corners,
  ) async {
    if (corners.isEmpty) return imageBytes;

    // Isolate.run automatically handles the isolate lifecycle and returns the result.
    return await Isolate.run(() async {
      return _annotateImageSync(imageBytes, corners);
    });
  }

  /// The synchronous function that actually draws the path on the canvas.
  /// Executed inside the isolate.
  static Future<Uint8List?> _annotateImageSync(
    Uint8List imageBytes,
    List<Point> corners,
  ) async {
    try {
      final codec = await ui.instantiateImageCodec(imageBytes);
      final frameInfo = await codec.getNextFrame();
      final image = frameInfo.image;

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);

      // Draw the original camera capture
      canvas.drawImage(image, ui.Offset.zero, ui.Paint());

      // Configure the bounding box stroke
      final paint = ui.Paint()
        ..color = const ui.Color(0xFF00FF00) // Bright Green
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 8.0
        ..strokeJoin = ui.StrokeJoin.round;

      // Map the corners to a Path
      final path = ui.Path();
      if (corners.isNotEmpty) {
        path.moveTo(corners[0].x, corners[0].y);
        for (int i = 1; i < corners.length; i++) {
          path.lineTo(corners[i].x, corners[i].y);
        }
        path.close(); // Connect last point back to the first
      }

      // Draw the bounding box onto the canvas
      canvas.drawPath(path, paint);

      // Extract the new composite image
      final picture = recorder.endRecording();
      final img = await picture.toImage(image.width, image.height);

      // Convert back to bytes (PNG encoding)
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      // If rendering fails (e.g., unsupported format), fallback to original image
      return imageBytes;
    }
  }
}
