import 'dart:typed_data';
import 'package:flutter_full_screen_scanner_platform_interface/flutter_full_screen_scanner_platform_interface.dart';

/// The type of event emitted by the scanner.
enum ScannerEventType {
  scanned,
  duplicate,
  detecting,
  captured,
  paused,
  resumed,
  error,
  cameraReady,
  flashChanged,
  cameraChanged,
}

/// Represents an event emitted from the scanner controller.
class ScannerEvent {
  /// The specific type of the event.
  final ScannerEventType type;

  /// Optional data payload associated with the event (e.g., the [ScannerResult] for 'scanned').
  final dynamic data;

  const ScannerEvent({required this.type, this.data});
}

/// Represents a point in the image where the barcode was found.
class Point {
  final double x;
  final double y;

  const Point({required this.x, required this.y});

  /// Maps from Pigeon-generated data class.
  factory Point.fromData(PointData data) {
    return Point(x: data.x ?? 0.0, y: data.y ?? 0.0);
  }
}

/// The result returned after a successful barcode scan.
class ScannerResult {
  /// The raw string value of the scanned barcode.
  final String value;

  /// The type of barcode detected (e.g., 'QR_CODE', 'CODE_128').
  final String type;

  /// Optional high-resolution image bytes captured at the time of the scan.
  final Uint8List? imageBytes;

  /// The corners of the detected barcode in the image.
  final List<Point>? corners;

  /// The width of the source image.
  final int? imageWidth;

  /// The height of the source image.
  final int? imageHeight;

  /// The timestamp (milliseconds since epoch) when the scan occurred.
  final int timestamp;

  const ScannerResult({
    required this.value,
    required this.type,
    this.imageBytes,
    this.corners,
    this.imageWidth,
    this.imageHeight,
    required this.timestamp,
  });

  /// Creates a user-facing [ScannerResult] from the Pigeon-generated [ScannerResultData].
  factory ScannerResult.fromData(ScannerResultData data) {
    return ScannerResult(
      value: data.value ?? '',
      type: data.type ?? 'UNKNOWN',
      imageBytes: data.imageBytes,
      corners: data.corners
          ?.where((p) => p != null)
          .map((p) => Point.fromData(p!))
          .toList(),
      imageWidth: data.imageWidth,
      imageHeight: data.imageHeight,
      timestamp: data.timestamp ?? DateTime.now().millisecondsSinceEpoch,
    );
  }
}

/// Represents the current state of the scanner UI, used for custom overlays.
class ScannerState {
  /// Whether a barcode was successfully detected in the latest frame.
  final bool barcodeDetected;

  /// Whether the camera is currently capturing a high-res image.
  final bool capturing;

  /// Whether the scanner is active and searching for barcodes.
  final bool scanning;

  /// Whether the flash (torch) is currently enabled.
  final bool flashEnabled;

  /// Whether a duplicate barcode was ignored due to duplicate prevention settings.
  final bool duplicateDetected;

  /// The list of barcodes currently visible in the frame.
  final List<ScannerResult> currentDetectedBarcodes;

  /// Progress of an ongoing scan or capture (0.0 to 1.0).
  final double scanProgress;

  const ScannerState({
    this.barcodeDetected = false,
    this.capturing = false,
    this.scanning = false,
    this.flashEnabled = false,
    this.duplicateDetected = false,
    this.currentDetectedBarcodes = const [],
    this.scanProgress = 0.0,
  });

  ScannerState copyWith({
    bool? barcodeDetected,
    bool? capturing,
    bool? scanning,
    bool? flashEnabled,
    bool? duplicateDetected,
    List<ScannerResult>? currentDetectedBarcodes,
    double? scanProgress,
  }) {
    return ScannerState(
      barcodeDetected: barcodeDetected ?? this.barcodeDetected,
      capturing: capturing ?? this.capturing,
      scanning: scanning ?? this.scanning,
      flashEnabled: flashEnabled ?? this.flashEnabled,
      duplicateDetected: duplicateDetected ?? this.duplicateDetected,
      currentDetectedBarcodes:
          currentDetectedBarcodes ?? this.currentDetectedBarcodes,
      scanProgress: scanProgress ?? this.scanProgress,
    );
  }
}
