import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_full_screen_scanner/flutter_full_screen_scanner.dart';
import 'package:flutter_full_screen_scanner_platform_interface/flutter_full_screen_scanner_platform_interface.dart';

void main() {
  group('ScannerModels', () {
    test('ScannerResult.fromData correctly parses ScannerResultData', () {
      final data = ScannerResultData(
        value: '123456',
        type: 'QR_CODE',
        imageWidth: 1920,
        imageHeight: 1080,
        timestamp: 1625097600000,
        corners: [PointData(x: 10.0, y: 20.0), PointData(x: 100.0, y: 200.0)],
      );

      final result = ScannerResult.fromData(data);

      expect(result.value, '123456');
      expect(result.type, 'QR_CODE');
      expect(result.imageWidth, 1920);
      expect(result.imageHeight, 1080);
      expect(result.timestamp, 1625097600000);
      expect(result.corners?.length, 2);
      expect(result.corners?[0].x, 10.0);
      expect(result.corners?[0].y, 20.0);
      expect(result.imageBytes, isNull);
    });

    test('ScannerState copyWith updates only specified fields', () {
      const state = ScannerState(
        barcodeDetected: false,
        scanning: true,
        flashEnabled: false,
      );

      final updatedState = state.copyWith(
        barcodeDetected: true,
        flashEnabled: true,
      );

      expect(updatedState.barcodeDetected, true);
      expect(updatedState.scanning, true); // Unchanged
      expect(updatedState.flashEnabled, true);
    });
  });

  group('ScannerOptions', () {
    test('ScannerOptions creates correct default values', () {
      const options = ScannerOptions();

      expect(options.allowDuplicate, false);
      expect(options.duplicateDelay, 1500);
      expect(options.enableImageCapture, true);
      expect(options.enableImageAnnotation, true);
    });
  });
}
