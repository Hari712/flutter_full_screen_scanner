## 1.0.7
* Ensure all barcode corners are fully within the scan window (instead of just the centroid) to prevent partial/half-visible barcode scans.
* Remove autofocus range restriction (`.none` instead of `.near`) to improve focus on barcodes at varying distances.
* Increase default video zoom factor to `2.0` (from `1.5`) to help with camera focusing.

## 1.0.6
* Fix nearby/adjacent barcode collision by implementing native scan window containment check.
* Fix CALayer coordinate conversion thread safety issues by executing on main thread block.
* Fix aspect ratio scaling issues by rotating captured image orientation correctly.

## 1.0.5
* Restrict barcode scanning strictly to the active `scanWindow` area (if configured).
* Prevent partial/half-visible barcode scans at the screen boundaries.
* Add NSLock thread synchronization around pending scan data to prevent race conditions and freezes.
* Optimize scanning speed and CPU usage by immediately dispatching results and skipping frame extraction when `enableImageCapture` is false.

## 1.0.4
* Bumped version to match main package.

## 1.0.3
* Update SDK environment constraints and dependency versions for Flutter 3.x compatibility.

## 1.0.2
* Update documentation references to version 1.0.2.

## 1.0.1
* Fix repository URLs in pubspec.yaml

## 1.0.0

* Initial release of the iOS platform implementation.
* Integrates native AVFoundation for direct hardware scanner control.
* Supports high-resolution, uncompressed 1080p image capture simultaneously with scanning.
* Dynamic interface orientation tracking for consistent preview rotation.
* Supports dynamic coordinate mapping for Flutter UI overlay synchronization.
