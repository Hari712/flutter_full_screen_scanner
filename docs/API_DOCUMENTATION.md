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
