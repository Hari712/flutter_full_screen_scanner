# Full Screen Scanner SDK

[![pub package](https://img.shields.io/pub/v/flutter_full_screen_scanner.svg)](https://pub.dev/packages/flutter_full_screen_scanner)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](https://opensource.org/licenses/MIT)

A production-ready, federated Flutter plugin monorepo for high-performance, full-screen continuous barcode and QR code scanning. Built with native CameraX & ML Kit on Android and AVFoundation & Apple Vision on iOS.

---

## Packages

| Package | Version | Description |
|---|---|---|
| [flutter_full_screen_scanner](flutter_full_screen_scanner) | [![pub package](https://img.shields.io/pub/v/flutter_full_screen_scanner.svg)](https://pub.dev/packages/flutter_full_screen_scanner) | The main app-facing package containing widgets, overlays, models, and controllers. |
| [flutter_full_screen_scanner_platform_interface](flutter_full_screen_scanner_platform_interface) | [![pub package](https://img.shields.io/pub/v/flutter_full_screen_scanner_platform_interface.svg)](https://pub.dev/packages/flutter_full_screen_scanner_platform_interface) | Abstract platform interface and Pigeon data models. |
| [flutter_full_screen_scanner_android](flutter_full_screen_scanner_android) | [![pub package](https://img.shields.io/pub/v/flutter_full_screen_scanner_android.svg)](https://pub.dev/packages/flutter_full_screen_scanner_android) | Native CameraX and Google ML Kit implementation for Android. |
| [flutter_full_screen_scanner_ios](flutter_full_screen_scanner_ios) | [![pub package](https://img.shields.io/pub/v/flutter_full_screen_scanner_ios.svg)](https://pub.dev/packages/flutter_full_screen_scanner_ios) | Native AVFoundation and Apple Vision implementation for iOS. |

---

## Quick Integration

Add the main package to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_full_screen_scanner: ^1.1.3
```

### Basic Example

```dart
import 'package:flutter/material.dart';
import 'package:flutter_full_screen_scanner/flutter_full_screen_scanner.dart';

class ScannerScreen extends StatelessWidget {
  const ScannerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FullScreenScanner(
        options: const ScannerOptions(
          scanMode: ScanMode.all,
          continuous: true,
          scanWindow: ScanWindow(widthFactor: 0.85, heightFactor: 0.35),
          allowDuplicate: false,
          duplicateDelay: 1500,
        ),
        onScan: (ScannerResult result) {
          debugPrint('Scanned: ${result.value} (${result.type})');
        },
      ),
    );
  }
}
```

For the complete integration guide, custom overlay HUD setup, and API documentation, see the [flutter_full_screen_scanner README](flutter_full_screen_scanner/README.md).

---

## ScannerOptions Reference

| Option | Type | Default | Platform | Description |
|---|---|---|---|---|
| `scanMode` | `ScanMode` | `ScanMode.barcode` | Both | `ScanMode.barcode`, `ScanMode.qr`, or `ScanMode.all`. |
| `continuous` | `bool` | `true` | Both | Continuous real-time detection vs single-scan mode. |
| `supportedFormats` | `List<BarcodeFormat>` | `[allFormats]` | Both | Restricts scanning to specific barcode formats. |
| `scanWindow` | `ScanWindow?` | `null` | Both | Fractional scan bounding box (`widthFactor`, `heightFactor`). |
| `allowDuplicate` | `bool` | `false` | Both | Whether to emit duplicate detections immediately. |
| `duplicateDelay` | `int` | `1500` ms | Both | Cooldown delay in ms before re-scanning the same barcode. |
| `scanInterval` | `int` | `50` ms | Both | Minimum interval in ms between camera frame analysis passes. |
| `enableImageCapture` | `bool` | `true` | Both | Extracts high-res cropped JPEG bytes of scanned barcodes. |
| `rejectBlurryImages` | `bool` | `false` | Both | Opt-in Laplacian sharpness check to reject blurry photos. |
| `blurThreshold` | `double` | `35.0` | Both | Laplacian variance threshold for blur rejection. |
| `requireConsecutiveMatches` | `int` | `1` | Both | Consecutive frames required for weak-checksum formats (Code 39, ITF). |
| `minConfirmations` | `int` | `2` | Both | Confirmation frame count before accepting detections. |
| `confidenceThreshold` | `double` | `0.5` | Both | Confidence score threshold (0.0 to 1.0). |
| `maxExposureDurationSeconds` | `double?` | `null` | iOS | Maximum camera exposure duration clamp. |
| `autoZoom` | `bool` | `true` | Both | Automatic zoom optimization. |
| `imageQuality` | `double` | `1.0` | Both | JPEG compression quality (0.0 to 1.0). |
| `enableFlash` | `bool` | `true` | Both | Enables hardware torch/flash controls. |
| `enableCameraSwitch` | `bool` | `true` | Both | Enables camera toggling (front/back). |
| `enableGallery` | `bool` | `true` | Both | Enables static image scanning. |
| `enableBeep` | `bool` | `true` | Both | Audio beep feedback on scan. |
| `enableVibration` | `bool` | `true` | Both | Haptic feedback vibration on scan. |
| `enableImageAnnotation` | `bool` | `true` | Both | Tracks corner coordinates for bounding box annotations. |

---

## Monorepo Development

This repository uses [Melos](https://melos.invertase.dev/) to manage all federated packages.

```bash
# Bootstrap dependencies across packages
dart run melos bootstrap

# Format all code
dart run melos run format

# Run analyzer across all packages
dart run melos run analyze

# Run publish dry-run across all packages
dart run melos run publish-dry-run
```

---

## License

MIT License. See [LICENSE](LICENSE) for details.
