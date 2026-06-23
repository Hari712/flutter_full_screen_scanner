import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'flutter_full_screen_scanner_ios_platform_interface.dart';

/// An implementation of [FlutterFullScreenScannerIosPlatform] that uses method channels.
class MethodChannelFlutterFullScreenScannerIos extends FlutterFullScreenScannerIosPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_full_screen_scanner_ios');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}
