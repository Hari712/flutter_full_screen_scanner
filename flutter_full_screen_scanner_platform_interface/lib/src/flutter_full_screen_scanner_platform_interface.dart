import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'messages.g.dart';
///
/// Platform implementations should extend this class rather than implement it.
/// Extending this class (using `extends`) ensures that the subclass will get
/// the default implementation, avoiding breaking changes when new methods are added.
abstract class FlutterFullScreenScannerPlatform extends PlatformInterface {
  /// Constructs a FlutterFullScreenScannerPlatform.
  FlutterFullScreenScannerPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterFullScreenScannerPlatform _instance = _PigeonImplementation();

  /// The default instance of [FlutterFullScreenScannerPlatform] to use.
  ///
  /// Defaults to [_PlaceholderImplementation].
  static FlutterFullScreenScannerPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [FlutterFullScreenScannerPlatform] when
  /// they register themselves.
  static set instance(FlutterFullScreenScannerPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Pauses the camera scanner.
  Future<void> pause() {
    throw UnimplementedError('pause() has not been implemented.');
  }

  /// Resumes the camera scanner.
  Future<void> resume() {
    throw UnimplementedError('resume() has not been implemented.');
  }

  /// Stops the camera scanner completely.
  Future<void> stop() {
    throw UnimplementedError('stop() has not been implemented.');
  }

  /// Toggles the device flash.
  /// Returns the new flash state (true for on, false for off).
  Future<bool> toggleFlash() {
    throw UnimplementedError('toggleFlash() has not been implemented.');
  }

  /// Switches the camera (e.g., from back to front).
  Future<void> switchCamera() {
    throw UnimplementedError('switchCamera() has not been implemented.');
  }

  /// Focuses the camera at the given coordinates.
  Future<void> focusAt(double x, double y) {
    throw UnimplementedError('focusAt() has not been implemented.');
  }

  /// Scans a specific image (e.g., from the gallery) and returns the decoded results.
  /// Returns a list of strings (barcode values) or models.
  Future<List<ScannerResultData?>> scanImage(String path) {
    throw UnimplementedError('scanImage() has not been implemented.');
  }

  /// Disposes the scanner and releases resources.
  Future<void> dispose() {
    throw UnimplementedError('dispose() has not been implemented.');
  }
}

class _PigeonImplementation extends FlutterFullScreenScannerPlatform {
  final ScannerHostApi _api = ScannerHostApi();

  @override
  Future<void> pause() async {
    await _api.pause();
  }

  @override
  Future<void> resume() async {
    await _api.resume();
  }

  @override
  Future<void> stop() async {
    await _api.stop();
  }

  @override
  Future<bool> toggleFlash() async {
    return await _api.toggleFlash();
  }

  @override
  Future<void> switchCamera() async {
    await _api.switchCamera();
  }

  @override
  Future<void> focusAt(double x, double y) async {
    await _api.focusAt(x, y);
  }

  @override
  Future<List<ScannerResultData?>> scanImage(String path) async {
    return await _api.scanImage(path);
  }

  @override
  Future<void> dispose() async {
    await _api.dispose();
  }
}
