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
