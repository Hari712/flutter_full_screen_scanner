import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_full_screen_scanner_platform_interface/flutter_full_screen_scanner_platform_interface.dart';
import 'scanner_models.dart';

/// The controller responsible for communicating with the native scanner platform.
class ScannerController extends ChangeNotifier {
  final FlutterFullScreenScannerPlatform _platform =
      FlutterFullScreenScannerPlatform.instance;

  // -- Properties --

  bool _isScanning = false;

  /// Whether the scanner is currently active and scanning.
  bool get isScanning => _isScanning;

  bool _isPaused = false;

  /// Whether the scanner is currently paused.
  bool get isPaused => _isPaused;

  bool _flashEnabled = false;

  /// Whether the device flash (torch) is currently on.
  bool get flashEnabled => _flashEnabled;

  // Assuming 0 represents the back camera and 1 represents the front camera.
  int _cameraFacing = 0;

  /// The current active camera facing direction.
  int get cameraFacing => _cameraFacing;

  final StreamController<ScannerEvent> _eventController =
      StreamController<ScannerEvent>.broadcast();

  /// A broadcast stream of all scanner events.
  Stream<ScannerEvent> get events => _eventController.stream;

  static const EventChannel _nativeEventChannel = EventChannel(
    'flutter_full_screen_scanner_events',
  );
  StreamSubscription? _eventSubscription;

  ScannerController() {
    _eventSubscription = _nativeEventChannel.receiveBroadcastStream().listen((
      dynamic event,
    ) {
      if (event is Map) {
        final type = event['type'] as String?;
        if (type == 'scanned') {
          final dataList = event['data'] as List?;
          if (dataList != null) {
            for (final item in dataList) {
              if (item is Map) {
                List<Point>? corners;
                final rawCorners = item['corners'] as List?;
                if (rawCorners != null) {
                  corners = rawCorners.map((c) {
                    final map = c as Map;
                    return Point(
                      x: (map['x'] as num).toDouble(),
                      y: (map['y'] as num).toDouble(),
                    );
                  }).toList();
                }

                final result = ScannerResult(
                  value: item['value']?.toString() ?? '',
                  type: item['type']?.toString() ?? '',
                  timestamp: item['timestamp'] as int? ??
                      DateTime.now().millisecondsSinceEpoch,
                  imageWidth: item['imageWidth'] as int?,
                  imageHeight: item['imageHeight'] as int?,
                  imageBytes: item['imageBytes'] as Uint8List?,
                  corners: corners,
                );
                _eventController.add(
                  ScannerEvent(type: ScannerEventType.scanned, data: result),
                );
              }
            }
          }
        }
      }
    });
  }

  // -- Methods --

  /// Pauses the camera scanner.
  Future<void> pause() async {
    await _platform.pause();
    _isPaused = true;
    _eventController.add(const ScannerEvent(type: ScannerEventType.paused));
    notifyListeners();
  }

  /// Resumes a paused camera scanner.
  Future<void> resume() async {
    await _platform.resume();
    _isPaused = false;
    _eventController.add(const ScannerEvent(type: ScannerEventType.resumed));
    notifyListeners();
  }

  /// Completely stops the camera scanner.
  Future<void> stop() async {
    await _platform.stop();
    _isScanning = false;
    notifyListeners();
  }

  /// Toggles the device flash (torch) on or off.
  Future<void> toggleFlash() async {
    final newState = await _platform.toggleFlash();
    _flashEnabled = newState;
    _eventController.add(
      ScannerEvent(type: ScannerEventType.flashChanged, data: _flashEnabled),
    );
    notifyListeners();
  }

  /// Switches the active camera (e.g., from back to front).
  Future<void> switchCamera() async {
    await _platform.switchCamera();
    // Toggle between 0 (back) and 1 (front) for now.
    _cameraFacing = _cameraFacing == 0 ? 1 : 0;
    _eventController.add(
      ScannerEvent(type: ScannerEventType.cameraChanged, data: _cameraFacing),
    );
    notifyListeners();
  }

  /// Focuses the camera at the given logical coordinates (usually tap-to-focus).
  Future<void> focusAt(double x, double y) async {
    await _platform.focusAt(x, y);
  }

  /// Scans a specific image from the file system (e.g., picked from gallery).
  Future<List<ScannerResult>> scanImage(String path) async {
    final results = await _platform.scanImage(path);
    return results
        .where((r) => r != null)
        .map((r) => ScannerResult.fromData(r as ScannerResultData))
        .toList();
  }

  /// Used internally to update scanning state from the native view creation.
  void internalSetScanning(bool scanning) {
    _isScanning = scanning;
    notifyListeners();
  }

  @override
  void dispose() {
    _platform.dispose();
    _eventSubscription?.cancel();
    _eventController.close();
    super.dispose();
  }
}
