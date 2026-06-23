import 'flutter_full_screen_scanner_android_platform_interface.dart';

class FlutterFullScreenScannerAndroid {
  Future<String?> getPlatformVersion() {
    return FlutterFullScreenScannerAndroidPlatform.instance
        .getPlatformVersion();
  }
}
