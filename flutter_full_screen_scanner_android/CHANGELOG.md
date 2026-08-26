## 1.1.2

- **PERF**: throttle MLKit barcode frame analysis to 150ms interval (~6.6 scans per second) to resolve high CPU usage, device heating, and camera preview lag on Android devices.

## 1.1.1

- **FIX**: resolve Android camera preview lag by processing ML Kit barcode scanning synchronously on the analyzer thread. This ensures correct frame backpressure handling and avoids buffer starvation.

## 1.1.0

 - **FIX**(android): resolve memory leak/crash by recycling bitmaps in BarcodeAnalyzer & bump to v1.0.9.
 - **FEAT**: implement laplacian blur detection and resolve android scanner coordinates mapping and scan window issues.
 - **FEAT**: implement configurable barcode formats and add boundary filtering for scanned barcodes on Android.
 - **FEAT**: Initial commit of Full Screen Scanner SDK.
 - **DOCS**: update CHANGELOGs for federated packages to 1.0.4.
 - **DOCS**: update README files to version 1.0.4.
 - **DOCS**: update package version references to 1.0.1.
 - **DOCS**: add 1.0.1 to changelog for pub.dev publish.

## 1.0.9
* Fixed memory leak and potential crash in `BarcodeAnalyzer` by properly recycling source and rotated bitmaps in the success and final execution blocks.

## 1.0.8
* Fixed coordinate double-rotation bug where barcode coordinate mapping was shifted.
* Switched camera preview to COMPATIBLE mode (TextureView) and configured explicit Aspect Fill scaling (`FILL_CENTER`) to resolve stretching/distortion and restore visibility of Flutter UI overlays.
* Mapped ML Kit barcode format constants to standard iOS/AVFoundation equivalent strings (e.g. `org.iso.QRCode`) to align scan mode filtering behavior exactly with iOS.
* Removed default 2x zoom (defaulting to 1.0x).

## 1.0.7
* Ensure all barcode corners are fully within the scan window (instead of just the centroid) to prevent partial/half-visible barcode scans.

## 1.0.6
* Bumped version to match main package.

## 1.0.5
* Restrict barcode scanning strictly to the active `scanWindow` area (if configured).
* Prevent partial/half-visible barcode scans at the screen or image boundaries.
* Resolve random camera analyzer freezes by ensuring the `ImageProxy` is always safely closed on success, failure, and execution error paths.
* Skip bitmap conversion and JPEG compression when `enableImageCapture` is false.

## 1.0.4
* Bumped version to match main package.

## 1.0.3
* Improve CameraX analyzer stability, handle life-cycle events and update SDK environment constraints.

## 1.0.2
* Update documentation references to version 1.0.2.

## 1.0.1
* Fix repository URLs in pubspec.yaml

## 1.0.0

* Initial release of the Android platform implementation.
* Integrates Android CameraX for lifecycle-aware camera management.
* Integrates Google ML Kit Vision for blazing fast local barcode detection.
* Supports high-resolution uncompressed image capture.
* Supports dynamic coordinate mapping over PlatformViews.
