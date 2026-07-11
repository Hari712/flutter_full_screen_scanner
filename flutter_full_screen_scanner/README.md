# Flutter Full Screen Scanner

A production-ready, highly optimized Flutter plugin for continuous, full-screen barcode and QR code scanning. Built with pure native implementations (CameraX and ML Kit on Android, AVFoundation on iOS) to ensure blazing fast, zero-jank performance.

## Features

- **Blazing Fast**: Uses ML Kit on Android and native AVFoundation on iOS.
- **Continuous Scanning**: Capable of detecting and tracking multiple barcodes continuously in real-time.
- **Customizable UI**: We provide the camera feed, you provide the overlay. Draw whatever you want on top of the scanner using the `overlayBuilder`.
- **Zero Flutter Camera Package Dependency**: Fully native implementations mean no overhead and no memory leaks from the standard Flutter camera package.
- **Duplicate Prevention**: Built-in cache system to debounce duplicate scans.
- **High Resolution Capture**: Seamlessly capture uncompressed 1080p images of scanned barcodes.
- **Dynamic Orientation**: Perfectly handles device rotation without interrupting the scan flow.

## Installation

Add the following to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_full_screen_scanner: ^1.0.5
```

## Android Setup

Update your `android/app/build.gradle` to ensure your `minSdkVersion` is at least 21.

```gradle
android {
    defaultConfig {
        minSdkVersion 21
    }
}
```

## iOS Setup

Add the camera usage description to your `ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>This app requires access to the camera to scan barcodes and QR codes.</string>
```

## Usage

```dart
import 'package:flutter/material.dart';
import 'package:flutter_full_screen_scanner/flutter_full_screen_scanner.dart';

class ScannerScreen extends StatefulWidget {
  @override
  _ScannerScreenState createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final ScannerController _controller = ScannerController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FullScreenScanner(
        controller: _controller,
        options: const ScannerOptions(
          allowDuplicate: false,
          duplicateDelay: 1500, // Debounce same barcode for 1.5s
          scanWindow: ScanWindow(widthFactor: 0.8, heightFactor: 0.3),
        ),
        onScan: (ScannerResult result) {
          print('Scanned: ${result.value} of type ${result.type}');
        },
        overlayBuilder: (context, state) {
          return ScannerCutoutOverlay(
            scanWindow: const ScanWindow(widthFactor: 0.8, heightFactor: 0.3),
            borderColor: state.barcodeDetected ? Colors.green : Colors.blue,
          );
        },
      ),
    );
  }
}
```

### ScannerOptions

Configure the scanner settings via the `ScannerOptions` class:

* **`scanWindow`**: Restricts the active scan area (defined as a `ScanWindow` with coordinate factors from `0.0` to `1.0`). Only barcodes fully visible and positioned entirely within this cutout area are detected.
* **`enableImageCapture`**: Set to `false` to disable retrieving barcode image bytes (`imageBytes`). Doing so disables raw image frame extraction and JPEG compression on the native thread, significantly reducing CPU usage and enabling smoother continuous scanning.
* **`allowDuplicate` & `duplicateDelay`**: Configure duplicate detection and cooling down periods.

### Controller API

The `ScannerController` gives you full programmatic control over the hardware:

- `pause()`: Pauses the camera feed and scanner.
- `resume()`: Resumes the camera feed and scanner.
- `stop()`: Shuts down the scanner entirely.
- `toggleFlash()`: Turns the device torch on or off.
- `switchCamera()`: Flips between the front and back cameras.
- `scanImage(String path)`: Scans a static image from the filesystem for barcodes.

## Extensibility

This SDK is designed to be highly extensible. The `overlayBuilder` exposes the raw `ScannerState` on every frame, allowing you to draw bounding boxes, animate crosshairs, or display interactive UI elements perfectly aligned with the real world.
