import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'flutter_full_screen_scanner_ios_method_channel.dart';

abstract class FlutterFullScreenScannerIosPlatform extends PlatformInterface {
  /// Constructs a FlutterFullScreenScannerIosPlatform.
  FlutterFullScreenScannerIosPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterFullScreenScannerIosPlatform _instance = MethodChannelFlutterFullScreenScannerIos();

  /// The default instance of [FlutterFullScreenScannerIosPlatform] to use.
  ///
  /// Defaults to [MethodChannelFlutterFullScreenScannerIos].
  static FlutterFullScreenScannerIosPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [FlutterFullScreenScannerIosPlatform] when
  /// they register themselves.
  static set instance(FlutterFullScreenScannerIosPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
