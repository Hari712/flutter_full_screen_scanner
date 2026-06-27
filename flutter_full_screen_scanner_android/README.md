# flutter_full_screen_scanner_android

The Android implementation of the `flutter_full_screen_scanner` plugin.

This package provides the native Android implementation of the scanner using CameraX for hardware acceleration and Google ML Kit for high-performance barcode and QR code detection.

## Usage

This package is an internal dependency of the `flutter_full_screen_scanner` plugin. You should not depend on this package directly in your Flutter app. 

Instead, please depend on the main plugin:

```yaml
dependencies:
  flutter_full_screen_scanner: ^1.0.2
```

## Architecture

This package leverages:
- **CameraX**: For handling complex lifecycle states, preview rendering, and image analysis pipelines.
- **Google ML Kit**: For on-device, low-latency barcode scanning without requiring an internet connection.
- **Platform Views**: To render the native camera preview seamlessly beneath your Flutter UI overlay.
