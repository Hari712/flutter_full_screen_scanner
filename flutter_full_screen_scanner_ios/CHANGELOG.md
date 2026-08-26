## 1.1.2

- **CHORE**: Bump version to 1.1.2 for release consistency.

## 1.1.1

- **CHORE**: Bump version to 1.1.1 for platform implementation consistency and release.

## 1.1.0

 - **FIX**(android): resolve memory leak/crash by recycling bitmaps in BarcodeAnalyzer & bump to v1.0.9.
 - **FIX**(ios): Resolve 1D barcode rotation, aspect-ratio bounds mapping, and main thread block.
 - **FEAT**: implement laplacian blur detection and resolve android scanner coordinates mapping and scan window issues.
 - **FEAT**: Initial commit of Full Screen Scanner SDK.
 - **DOCS**: update CHANGELOGs for federated packages to 1.0.4.
 - **DOCS**: update README files to version 1.0.4.
 - **DOCS**: update package version references to 1.0.1.
 - **DOCS**: add 1.0.1 to changelog for pub.dev publish.

## 1.0.9
* Bumped version to match main package for compatibility.

## 1.0.8
* Removed default zoom (defaulting to 1.0x) to match the Android behavior.

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
