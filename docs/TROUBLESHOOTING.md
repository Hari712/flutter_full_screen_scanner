# Troubleshooting

## Scanner Feed is Black on Android
1. Ensure you have defined the `<uses-permission android:name="android.permission.CAMERA" />` in your `AndroidManifest.xml`.
2. Ensure you have dynamically requested the Camera permission at runtime in Dart (using a package like `permission_handler`) *before* pushing the `ScannerScreen` to the navigator.

## App Crashes on iOS immediately upon opening scanner
You must include the `NSCameraUsageDescription` in your `Info.plist`. Without this, iOS will kill the application instantly upon initialization of `AVCaptureSession`.

## Bounding Boxes Are Misaligned
Ensure that you are taking the `devicePixelRatio` into account if you are performing manual coordinate translations. The SDK handles coordinate normalization automatically via the `scanWindow` and `overlayBuilder`, but if you draw on a raw canvas, remember that ML Kit and AVFoundation return physical sensor coordinates.

## "CameraX not found" Build Error
Ensure your Android `minSdkVersion` is set to 21 or higher. CameraX is not compatible with older Android versions.
