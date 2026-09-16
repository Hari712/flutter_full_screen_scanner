# Flutter Full Screen Scanner

[![pub package](https://img.shields.io/pub/v/flutter_full_screen_scanner.svg)](https://pub.dev/packages/flutter_full_screen_scanner)
[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS-blue.svg)](https://pub.dev/packages/flutter_full_screen_scanner)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](https://opensource.org/licenses/MIT)

A production-ready, high-performance Flutter plugin for continuous, full-screen barcode and QR code scanning. Built with pure native implementations (**CameraX and Google ML Kit** on Android, **AVFoundation and Vision** on iOS) to ensure blazing-fast scanning, zero-jank camera previews, intelligent motion gating, and crystal-clear image captures.

---

## Key Features

- ⚡ **Blazing Fast & Zero-Jank**: Direct native pipeline using Android CameraX + ML Kit and iOS AVFoundation + Apple Vision without standard Flutter camera overhead.
- 🔄 **Continuous Real-Time Scanning**: Smoothly detects, highlights, and tracks 1D barcodes and 2D QR codes in real time.
- 🎯 **Configurable Scan Window**: Restrict scanning to any fractional rectangular viewport with sub-millisecond boundary checks.
- 🏎️ **Pre-Decode Motion Gating**: Hardware sensor-assisted gating (gyroscope + linear acceleration) to suppress decoding during quick hand sweeps between targets.
- 📸 **Focus-Settled Image Capture**: Automatically waits for autofocus and autoexposure to settle before grabbing high-resolution barcode crops.
- 🔬 **Laplacian Blur Rejection**: Opt-in sharpness analyzer computes Laplacian variance and rejects blurry or out-of-focus captures.
- 🛡️ **Weak-Checksum Symbology Protection**: Frame-consecutive verification eliminates false positives on Code 39, ITF-14, and Codabar.
- 🎨 **Fully Customizable Overlay**: Built-in `ScannerCutoutOverlay` plus an open `overlayBuilder` to draw bounding boxes, badges, or animated reticles.
- 🖼️ **Gallery Image Scanning**: Programmatically scan saved photos or picked documents for barcodes.

---

## Installation

Add `flutter_full_screen_scanner` to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_full_screen_scanner: ^1.1.3
```

Then run:

```bash
flutter pub get
```

---

## Platform Setup

### Android Setup

1. In `android/app/build.gradle`, set `minSdkVersion` to at least **21**:

```gradle
android {
    defaultConfig {
        minSdkVersion 21
    }
}
```

2. *(Optional)* Add camera and sensor permissions to `android/app/src/main/AndroidManifest.xml` if not already present:

```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-feature android:name="android.hardware.camera" android:required="false" />
<uses-feature android:name="android.hardware.camera.autofocus" android:required="false" />
```

### iOS Setup

Add the camera usage description to `ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>This app requires camera access to scan barcodes and QR codes.</string>
```

---

## Integration Guide

### 1. Basic Quick Start

Use the `FullScreenScanner` widget to start scanning in seconds:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_full_screen_scanner/flutter_full_screen_scanner.dart';

class SimpleScannerScreen extends StatelessWidget {
  const SimpleScannerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Barcode Scanner')),
      body: FullScreenScanner(
        options: const ScannerOptions(
          scanMode: ScanMode.all,
          continuous: true,
          allowDuplicate: false,
          duplicateDelay: 1500, // 1.5 second cooldown per unique barcode
        ),
        onScan: (ScannerResult result) {
          debugPrint('Scanned barcode: ${result.value} (${result.type})');
        },
      ),
    );
  }
}
```

---

### 2. Advanced Integration with Custom Cutout Overlay & Controller

For full control over the flash, camera flip, scan region, and custom HUD overlays:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_full_screen_scanner/flutter_full_screen_scanner.dart';

class AdvancedScannerScreen extends StatefulWidget {
  const AdvancedScannerScreen({super.key});

  @override
  State<AdvancedScannerScreen> createState() => _AdvancedScannerScreenState();
}

class _AdvancedScannerScreenState extends State<AdvancedScannerScreen> {
  late final ScannerController _controller;
  final List<ScannerResult> _scannedItems = [];

  @override
  void initState() {
    super.initState();
    _controller = ScannerController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const scanWindow = ScanWindow(
      widthFactor: 0.85,
      heightFactor: 0.35,
    );

    return Scaffold(
      body: Stack(
        children: [
          // 1. Scanner Camera Feed
          FullScreenScanner(
            controller: _controller,
            options: const ScannerOptions(
              scanMode: ScanMode.all,
              continuous: true,
              scanWindow: scanWindow,
              allowDuplicate: false,
              duplicateDelay: 2000,
              scanInterval: 60, // Analyze frame every 60ms (~16 FPS)
              enableImageCapture: true, // Capture high-res crop
              rejectBlurryImages: true, // Reject blurry frames
              blurThreshold: 35.0,
              requireConsecutiveMatches: 2, // Extra safety for 1D barcodes
            ),
            onScan: (ScannerResult result) {
              setState(() {
                _scannedItems.insert(0, result);
              });

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Scanned: ${result.value}'),
                  duration: const Duration(milliseconds: 800),
                ),
              );
            },
            // 2. Custom Overlay HUD
            overlayBuilder: (context, state) {
              return Stack(
                children: [
                  ScannerCutoutOverlay(
                    scanWindow: scanWindow,
                    borderColor: state.barcodeDetected
                        ? Colors.greenAccent
                        : Colors.white,
                    borderWidth: 3.0,
                    borderRadius: 16.0,
                    overlayColor: Colors.black.withOpacity(0.55),
                  ),
                  if (state.capturing)
                    const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                ],
              );
            },
          ),

          // 3. Top Action Bar Controls
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.flash_on, color: Colors.white),
                        onPressed: () => _controller.toggleFlash(),
                      ),
                      IconButton(
                        icon: const Icon(Icons.flip_camera_ios, color: Colors.white),
                        onPressed: () => _controller.switchCamera(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

---

### 3. Scanning Images from Gallery / File System

You can decode barcodes from static local images without launching the live camera:

```dart
final ScannerController controller = ScannerController();

// Pass absolute file path to the image
final List<ScannerResult> results = await controller.scanImage('/path/to/image.jpg');

for (final result in results) {
  print('Found barcode in image: ${result.value} (${result.type})');
}
```

---

## ScannerOptions Reference

Every scanning behavior is configurable via `ScannerOptions`. Below is the complete reference table:

| Option | Type | Default | Platform | Description & How to Use |
|---|---|---|---|---|
| **`scanMode`** | `ScanMode` | `ScanMode.barcode` | Both | General scanning mode: `ScanMode.barcode` (1D barcodes), `ScanMode.qr` (2D QR codes), or `ScanMode.all` (both). |
| **`continuous`** | `bool` | `true` | Both | When `true`, scanner keeps listening for barcodes continuously. When `false`, halts after the first scan. |
| **`supportedFormats`** | `List<BarcodeFormat>` | `[BarcodeFormat.allFormats]` | Both | Restricts scanning to specific symbologies (e.g. `[BarcodeFormat.qrCode, BarcodeFormat.code128]`). Specifying only required formats boosts scanning performance and prevents unwanted detections. |
| **`scanWindow`** | `ScanWindow?` | `null` | Both | Defines the active scan viewport using relative screen proportions (`widthFactor: 0.0-1.0`, `heightFactor: 0.0-1.0`). Barcodes partially or fully outside this area are ignored. |
| **`allowDuplicate`** | `bool` | `false` | Both | If `true`, the exact same barcode can be emitted consecutively without delay. If `false`, duplicate suppression is active. |
| **`duplicateDelay`** | `int` | `1500` (ms) | Both | Cooldown time in milliseconds before the exact same barcode string is allowed to trigger `onScan` again when `allowDuplicate` is `false`. |
| **`scanInterval`** | `int` | `50` (ms) | Both | Minimum interval in milliseconds between frame analysis passes. Prevents high CPU usage, device heating, and camera preview lag. |
| **`enableImageCapture`** | `bool` | `true` | Both | When `true`, extracts and returns high-resolution cropped JPEG bytes of the scanned barcode in `ScannerResult.imageBytes`. Set to `false` for maximum FPS and lowest memory consumption. |
| **`rejectBlurryImages`** | `bool` | `false` | Both | Opt-in Laplacian variance sharpness analyzer. Evaluates the cropped frame and marks `imageRejected: true` (or skips compression) if the image is out of focus. |
| **`blurThreshold`** | `double` | `35.0` | Both | Sharpness threshold used when `rejectBlurryImages: true`. Lower values (e.g. `20.0`) are more lenient; higher values (e.g. `60.0`) require crisper focus. |
| **`requireConsecutiveMatches`** | `int` | `1` | Both | Number of consecutive matching frames required before emitting weak-checksum formats (Code 39, ITF-14, Codabar). Set to `2` or `3` to completely eliminate misreads on 1D labels. |
| **`minConfirmations`** | `int` | `2` | Both | Number of confirmation frames required before accepting a barcode candidate. |
| **`confidenceThreshold`** | `double` | `0.5` | Both | Detection confidence threshold (`0.0` to `1.0`) for ML Kit / Apple Vision bounding box quality. |
| **`maxExposureDurationSeconds`** | `double?` | `null` | iOS | Clamps the maximum camera exposure duration (e.g., `1.0 / 60.0`) to trade low-light brightness for reduced motion blur. |
| **`autoZoom`** | `bool` | `true` | Both | Enables automatic camera zoom optimization when scanning small or distant barcodes. |
| **`imageQuality`** | `double` | `1.0` | Both | Compression quality (`0.0` to `1.0`) for JPEG image bytes generated during barcode capture. |
| **`enableFlash`** | `bool` | `true` | Both | Enables hardware torch/flash capability on the device camera. |
| **`enableCameraSwitch`** | `bool` | `true` | Both | Enables flipping between front and rear cameras. |
| **`enableGallery`** | `bool` | `true` | Both | Enables static image scanning capabilities. |
| **`enableBeep`** | `bool` | `true` | Both | Emits an audio beep feedback on a successful barcode detection. |
| **`enableVibration`** | `bool` | `true` | Both | Triggers short haptic feedback / vibration on successful barcode detection. |
| **`enableImageAnnotation`** | `bool` | `true` | Both | Automatically tracks detected corner coordinates for bounding box annotations. |

---

## ScannerResult Reference

The `onScan` callback receives a `ScannerResult` instance with rich detection details:

| Field | Type | Description |
|---|---|---|
| `value` | `String` | Decoded string value of the barcode. |
| `type` | `String` | Detected format name (e.g., `QR_CODE`, `CODE_128`, `EAN_13`). |
| `imageBytes` | `Uint8List?` | High-resolution cropped JPEG bytes of the barcode (null if `enableImageCapture` is false or image was rejected). |
| `corners` | `List<Point>?` | Detected corner points (`x`, `y`) relative to the cropped barcode bounds. |
| `imageWidth` | `int?` | Pixel width of the captured barcode image. |
| `imageHeight` | `int?` | Pixel height of the captured barcode image. |
| `timestamp` | `int` | Millisecond timestamp when the scan occurred. |
| `imageRejected` | `bool` | `true` if image capture was skipped or discarded due to blur or autofocus settling. |
| `imageRejectReason` | `String?` | Specific rejection cause: `'blurry'` (Laplacian variance below threshold) or `'focusSettling'` (AF/AE still racking). |
| `sharpnessScore` | `double?` | Raw Laplacian variance score computed for the image. |
| `motionRisk` | `double?` | Estimated motion blur risk based on gyroscope rotation rate and sensor exposure time. |

---

## ScannerController API

Manage the camera and scanner programmatically:

```dart
final controller = ScannerController();

// Methods
await controller.pause();            // Pauses the camera feed & analysis
await controller.resume();           // Resumes paused camera feed
await controller.stop();             // Stops camera pipeline
await controller.toggleFlash();      // Toggles torch on/off
await controller.switchCamera();     // Switches front/rear camera
await controller.focusAt(x, y);      // Sets tap-to-focus point (0.0 to 1.0)
await controller.scanImage(path);    // Decodes barcodes from a local image file
controller.dispose();                // Releases resources

// Properties & Streams
bool isScanning = controller.isScanning;
bool isPaused = controller.isPaused;
bool flashOn = controller.flashEnabled;
int facing = controller.cameraFacing; // 0 = back, 1 = front
Stream<ScannerEvent> events = controller.events; // Stream of all scanner events
```

---

## Supported Barcode Symbologies

| 1D Barcodes | 2D Barcodes |
|---|---|
| `BarcodeFormat.code128` | `BarcodeFormat.qrCode` |
| `BarcodeFormat.code39` | `BarcodeFormat.dataMatrix` |
| `BarcodeFormat.code93` | `BarcodeFormat.pdf417` |
| `BarcodeFormat.ean13` | `BarcodeFormat.aztec` |
| `BarcodeFormat.ean8` | |
| `BarcodeFormat.upcA` | |
| `BarcodeFormat.upcE` | |
| `BarcodeFormat.itf` (ITF-14) | |
| `BarcodeFormat.codaBar` | |

---

## Best Practices & Performance Tips

1. **Limit `supportedFormats`**: If your app only needs QR codes or Code 128, specify only those formats in `ScannerOptions(supportedFormats: [BarcodeFormat.qrCode, BarcodeFormat.code128])`. This prevents the engine from running redundant decoders on every frame.
2. **Use `scanWindow`**: Restricting scanning to a centered box (e.g. `ScanWindow(widthFactor: 0.8, heightFactor: 0.35)`) reduces the search space and avoids scanning neighboring barcodes on crowded inventory labels.
3. **Disable `enableImageCapture` if bytes aren't needed**: If you only need barcode string values (and not image photos), set `enableImageCapture: false` to skip frame extraction and JPEG compression entirely.
4. **Use `requireConsecutiveMatches: 2` for Code 39 / ITF**: Symbologies without mandatory checksums can occasionally produce 1-frame misreads on low-contrast surfaces. Setting `requireConsecutiveMatches: 2` ensures 100% accuracy.

---

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
