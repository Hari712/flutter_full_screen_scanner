# Installation Guide

## 1. Add Dependency
Add the plugin to your `pubspec.yaml`:
```yaml
dependencies:
  flutter_full_screen_scanner: ^1.0.0
```

## 2. Android Configuration
Update your `android/app/build.gradle` to set the minimum SDK version:
```gradle
android {
    defaultConfig {
        minSdkVersion 21 // Required by CameraX and ML Kit
    }
}
```

## 3. iOS Configuration
Add the NSCameraUsageDescription to your `ios/Runner/Info.plist`:
```xml
<key>NSCameraUsageDescription</key>
<string>This app requires access to the camera to scan barcodes and QR codes.</string>
```

## 4. Import
```dart
import 'package:flutter_full_screen_scanner/flutter_full_screen_scanner.dart';
```
