# Architecture Documentation

## Federated Plugin Structure

The SDK is built using Flutter's federated plugin architecture, consisting of four interdependent packages:

1. **`flutter_full_screen_scanner`**: The app-facing package. Provides the declarative `FullScreenScanner` widget, `ScannerController`, and `ScannerOptions`.
2. **`flutter_full_screen_scanner_platform_interface`**: Uses Pigeon to auto-generate type-safe message passing channels between Dart and the host platforms.
3. **`flutter_full_screen_scanner_android`**: Native Kotlin implementation using CameraX to manage the lifecycle and ML Kit Vision for parsing the video feed on a background thread.
4. **`flutter_full_screen_scanner_ios`**: Native Swift implementation using AVFoundation to stream `CVPixelBuffer`s to the metadata output pipeline concurrently.

## Why Native over Flutter Camera?

Most Flutter barcode scanners depend on the official `camera` plugin. This SDK does not. By owning the camera hardware interface natively, we eliminate memory leaks caused by passing heavy image buffers over the MethodChannel, ensuring continuous scanning remains locked at 60 FPS.
