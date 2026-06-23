import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'flutter_full_screen_scanner_android_method_channel.dart';

abstract class FlutterFullScreenScannerAndroidPlatform extends PlatformInterface {
  /// Constructs a FlutterFullScreenScannerAndroidPlatform.
  FlutterFullScreenScannerAndroidPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterFullScreenScannerAndroidPlatform _instance = MethodChannelFlutterFullScreenScannerAndroid();

  /// The default instance of [FlutterFullScreenScannerAndroidPlatform] to use.
  ///
  /// Defaults to [MethodChannelFlutterFullScreenScannerAndroid].
  static FlutterFullScreenScannerAndroidPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [FlutterFullScreenScannerAndroidPlatform] when
  /// they register themselves.
  static set instance(FlutterFullScreenScannerAndroidPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
