
import 'flutter_full_screen_scanner_ios_platform_interface.dart';

class FlutterFullScreenScannerIos {
  Future<String?> getPlatformVersion() {
    return FlutterFullScreenScannerIosPlatform.instance.getPlatformVersion();
  }
}
