## 1.0.9
* Android: Fixed memory leak and potential crash in `BarcodeAnalyzer` by properly recycling source and rotated bitmaps in success and final execution paths.
* Update platform implementation dependency constraints to `^1.0.9`.

## 1.0.8
* Android: Fixed coordinate double-rotation bug where barcode coordinate mapping was shifted, resolving the issue where valid barcodes were rejected by Dart's vertical boundaries check.
* Android: Switched camera preview to COMPATIBLE mode (TextureView) and configured explicit Aspect Fill scaling (`FILL_CENTER`). This resolves stretching/distortion issues and restores visibility of Flutter UI widgets (borders, buttons, overlays) layered on top of the camera preview.
* Android: Mapped ML Kit barcode formats to standard iOS format strings (e.g. `org.iso.QRCode`) to align scan mode filtering behavior exactly with iOS.
* Android: Configured default 1.0x zoom on both Android and iOS to align preview focus.
* Update platform implementation dependency constraints to `^1.0.8`.

## 1.0.7
* Android: Ensure all barcode corners are fully within the scan window (instead of just the centroid) to prevent partial/half-visible barcode scans.
* iOS: Ensure all barcode corners are fully within the scan window to prevent partial/half-visible barcode scans.
* iOS: Remove autofocus range restriction (`.none` instead of `.near`) to improve barcode focus at various distances.
* iOS: Increase default zoom factor to `2.0` (from `1.5`) for better barcode focus.
* Update platform implementation dependency constraints to `^1.0.7`.

## 1.0.6
* Fix nearby/adjacent barcode scanning issues on iOS with native scan window filtering.
* Fix iOS CALayer coordinate conversion thread safety issues.
* Fix aspect ratio scaling issues on iOS by correctly orienting captured frame images.

## 1.0.5
* Restrict barcode scanning strictly to the active `scanWindow` area (if configured).
* Prevent partial/half-visible barcode scans to avoid incorrect decoded text.
* Fix random camera analyzer freezes and thread safety issues on native platforms.
* Optimize scanning performance by skipping image capture and compression when `enableImageCapture` is false.
* Update platform implementation dependency constraints to `^1.0.5`.

## 1.0.4
* Removed debugging logs.

## 1.0.3
* Update dependencies to version 1.0.3 across platform implementations and refine SDK constraints.

## 1.0.2
* Update documentation and installation references to version 1.0.2.

## 1.0.1
* Fix repository URLs in pubspec.yaml

## 1.0.0

* Initial stable release of the Full Screen Scanner SDK.
* High-performance continuous native scanning (CameraX and AVFoundation).
* ML Kit integration on Android.
* Real-time coordinate mapping for bounding boxes.
* Added `FullScreenScanner` widget and `ScannerController`.
* Added `overlayBuilder` for extensive UI customization.
