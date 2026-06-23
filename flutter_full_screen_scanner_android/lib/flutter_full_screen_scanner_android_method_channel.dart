import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'flutter_full_screen_scanner_android_platform_interface.dart';

/// An implementation of [FlutterFullScreenScannerAndroidPlatform] that uses method channels.
class MethodChannelFlutterFullScreenScannerAndroid extends FlutterFullScreenScannerAndroidPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_full_screen_scanner_android');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}
