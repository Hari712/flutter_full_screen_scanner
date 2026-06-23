import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'flutter_full_screen_scanner_method_channel.dart';

abstract class FlutterFullScreenScannerPlatform extends PlatformInterface {
  /// Constructs a FlutterFullScreenScannerPlatform.
  FlutterFullScreenScannerPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterFullScreenScannerPlatform _instance =
      MethodChannelFlutterFullScreenScanner();

  /// The default instance of [FlutterFullScreenScannerPlatform] to use.
  ///
  /// Defaults to [MethodChannelFlutterFullScreenScanner].
  static FlutterFullScreenScannerPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [FlutterFullScreenScannerPlatform] when
  /// they register themselves.
  static set instance(FlutterFullScreenScannerPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
