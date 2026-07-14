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
