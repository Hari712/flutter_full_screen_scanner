# API Documentation

## `FullScreenScanner`
The main widget that initializes the camera and renders the overlay.
- `controller`: The `ScannerController` instance.
- `options`: `ScannerOptions` for configuration.
- `onScan`: Callback triggered when a barcode is successfully detected.
- `overlayBuilder`: A builder function `(BuildContext context, ScannerState state)` that returns the UI overlay.

## `ScannerController`
Exposes the underlying hardware.
- `pause()`: Pauses scanning.
- `resume()`: Resumes scanning.
- `stop()`: Halts the pipeline.
- `toggleFlash()`: Toggles the torch.
- `switchCamera()`: Switches front/back camera.
- `scanImage(String path)`: Scans a still image.

## `ScannerOptions`
- `allowDuplicate`: Allow identical consecutive scans.
- `duplicateDelay`: Milliseconds to debounce duplicates (default 1500).
- `scanWindow`: The restricted region of interest for scanning.
- `rejectBlurryImages`: Whether to reject blurry captured evidence images using Laplacian variance.
- `blurThreshold`: Sharpness variance score threshold (default 35.0) below which an image is considered blurry and rejected.

## `ScannerResult`
- `value`: The decoded barcode string value.
- `type`: The format of the barcode (e.g. qrCode, code128).
- `imageBytes`: Optional raw JPEG bytes of the captured barcode frame.
- `imageRejected`: Boolean indicating if the captured frame was rejected due to being blurry.
- `sharpnessScore`: The calculated Laplacian variance sharpness score of the barcode region.
