import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/messages.g.dart',
    dartOptions: DartOptions(),
    kotlinOut:
        '../flutter_full_screen_scanner_android/android/src/main/kotlin/com/example/flutter_full_screen_scanner_android/Messages.g.kt',
    kotlinOptions: KotlinOptions(
      package: 'com.example.flutter_full_screen_scanner_android',
    ),
    swiftOut:
        '../flutter_full_screen_scanner_ios/ios/flutter_full_screen_scanner_ios/Sources/flutter_full_screen_scanner_ios/Messages.g.swift',
    swiftOptions: SwiftOptions(),
  ),
)
enum ScanModeData { barcode, qr, all }

enum BarcodeFormatData {
  allFormats,
  code128,
  code39,
  code93,
  codaBar,
  dataMatrix,
  ean13,
  ean8,
  itf,
  qrCode,
  upcA,
  upcE,
  pdf417,
  aztec,
}

class ScanWindowData {
  double? widthFactor;
  double? heightFactor;
}

class ScannerOptionsData {
  ScanModeData? scanMode;
  bool? continuous;
  bool? enableFlash;
  bool? enableGallery;
  bool? enableCameraSwitch;
  bool? enableBeep;
  bool? enableVibration;
  bool? enableImageCapture;
  bool? enableImageAnnotation;
  bool? allowDuplicate;
  int? duplicateDelay;
  int? scanInterval;
  List<BarcodeFormatData?>? supportedFormats;
  ScanWindowData? scanWindow;
  bool? autoZoom;
  double? imageQuality;
  double? confidenceThreshold;
}

class PointData {
  double? x;
  double? y;
}

class ScannerResultData {
  String? value;
  String? type;
  Uint8List? imageBytes;
  List<PointData?>? corners;
  int? imageWidth;
  int? imageHeight;
  int? timestamp;
}

@HostApi()
abstract class ScannerHostApi {
  void pause();
  void resume();
  void stop();
  bool toggleFlash();
  void switchCamera();
  void focusAt(double x, double y);

  @async
  List<ScannerResultData?> scanImage(String path);

  void dispose();
}
