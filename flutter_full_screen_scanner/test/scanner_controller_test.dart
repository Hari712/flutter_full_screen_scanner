import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_full_screen_scanner/flutter_full_screen_scanner.dart';
import 'package:flutter_full_screen_scanner_platform_interface/flutter_full_screen_scanner_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockScannerPlatform extends FlutterFullScreenScannerPlatform
    with MockPlatformInterfaceMixin {
  bool isPaused = false;
  bool isFlashEnabled = false;
  int cameraSwitchedCount = 0;

  @override
  Future<void> pause() async {
    isPaused = true;
  }

  @override
  Future<void> resume() async {
    isPaused = false;
  }

  @override
  Future<bool> toggleFlash() async {
    isFlashEnabled = !isFlashEnabled;
    return isFlashEnabled;
  }

  @override
  Future<void> switchCamera() async {
    cameraSwitchedCount++;
  }

  @override
  Future<void> dispose() async {
    // Mock dispose
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ScannerController controller;
  late MockScannerPlatform mockPlatform;

  setUp(() {
    mockPlatform = MockScannerPlatform();
    FlutterFullScreenScannerPlatform.instance = mockPlatform;
    controller = ScannerController();
  });

  tearDown(() {
    controller.dispose();
  });

  group('ScannerController', () {
    test('pause calls platform method and updates state', () async {
      expect(controller.isPaused, false);
      await controller.pause();
      expect(mockPlatform.isPaused, true);
      expect(controller.isPaused, true);
    });

    test('resume calls platform method and updates state', () async {
      controller.internalSetScanning(true);
      await controller.pause();
      expect(controller.isPaused, true);

      await controller.resume();
      expect(mockPlatform.isPaused, false);
      expect(controller.isPaused, false);
    });

    test('toggleFlash toggles state', () async {
      expect(controller.flashEnabled, false);

      await controller.toggleFlash();
      expect(mockPlatform.isFlashEnabled, true);
      expect(controller.flashEnabled, true);

      await controller.toggleFlash();
      expect(mockPlatform.isFlashEnabled, false);
      expect(controller.flashEnabled, false);
    });

    test('switchCamera switches facing', () async {
      expect(controller.cameraFacing, 0); // Default back

      await controller.switchCamera();
      expect(mockPlatform.cameraSwitchedCount, 1);
      expect(controller.cameraFacing, 1); // Front
    });
  });
}
