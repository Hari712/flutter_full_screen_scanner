import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'flutter_full_screen_scanner_platform_interface.dart';

/// An implementation of [FlutterFullScreenScannerPlatform] that uses method channels.
class MethodChannelFlutterFullScreenScanner
    extends FlutterFullScreenScannerPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_full_screen_scanner');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}
