# flutter_full_screen_scanner_ios

The iOS implementation of the `flutter_full_screen_scanner` plugin.

This package provides the native iOS implementation of the scanner using `AVFoundation` for low-level hardware control, blazing fast barcode tracking, and uncompressed high-resolution image capture.

## Usage

This package is an internal dependency of the `flutter_full_screen_scanner` plugin. You should not depend on this package directly in your Flutter app. 

Instead, please depend on the main plugin:

```yaml
dependencies:
  flutter_full_screen_scanner: ^1.0.5
```

## Architecture

This package leverages:
- **AVFoundation**: For configuring multi-output capture sessions (`AVCaptureVideoDataOutput` and `AVCaptureMetadataOutput` simultaneously).
- **Vision Framework Mapping**: To dynamically map normalized barcode coordinates across varying UI rotations seamlessly.
- **Platform Views**: To render the native `AVCaptureVideoPreviewLayer` flawlessly beneath your Flutter overlay UI.
