import 'package:flutter_full_screen_scanner_platform_interface/flutter_full_screen_scanner_platform_interface.dart';

/// The mode of scanning.
enum ScanMode { barcode, qr, all }

extension ScanModeMapper on ScanMode {
  ScanModeData toData() {
    switch (this) {
      case ScanMode.barcode:
        return ScanModeData.barcode;
      case ScanMode.qr:
        return ScanModeData.qr;
      case ScanMode.all:
        return ScanModeData.all;
    }
  }
}

/// Supported barcode formats.
enum BarcodeFormat {
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

extension BarcodeFormatMapper on BarcodeFormat {
  BarcodeFormatData toData() {
    return BarcodeFormatData.values.firstWhere(
      (e) => e.name == name,
      orElse: () => BarcodeFormatData.allFormats,
    );
  }
}

/// Defines the target area for scanning within the camera view.
/// Only barcodes inside this area will be processed.
class ScanWindow {
  /// The width factor of the scan window relative to the screen width (0.0 to 1.0).
  final double widthFactor;

  /// The height factor of the scan window relative to the screen height (0.0 to 1.0).
  final double heightFactor;

  const ScanWindow({required this.widthFactor, required this.heightFactor});

  ScanWindowData toData() {
    return ScanWindowData(widthFactor: widthFactor, heightFactor: heightFactor);
  }
}

/// Configuration options for the full screen scanner.
class ScannerOptions {
  final ScanMode scanMode;
  final bool continuous;
  final bool enableFlash;
  final bool enableGallery;
  final bool enableCameraSwitch;
  final bool enableBeep;
  final bool enableVibration;
  final bool enableImageCapture;
  final bool enableImageAnnotation;
  final bool allowDuplicate;
  final int duplicateDelay; // in milliseconds
  final int scanInterval; // in milliseconds
  final List<BarcodeFormat> supportedFormats;
  final ScanWindow? scanWindow;
  final bool autoZoom;
  final double imageQuality; // 0.0 to 1.0
  final double confidenceThreshold; // 0.0 to 1.0

  const ScannerOptions({
    this.scanMode = ScanMode.barcode,
    this.continuous = true,
    this.enableFlash = true,
    this.enableGallery = true,
    this.enableCameraSwitch = true,
    this.enableBeep = true,
    this.enableVibration = true,
    this.enableImageCapture = true,
    this.enableImageAnnotation = true,
    this.allowDuplicate = false,
    this.duplicateDelay = 1500,
    this.scanInterval = 100,
    this.supportedFormats = const [BarcodeFormat.allFormats],
    this.scanWindow,
    this.autoZoom = true,
    this.imageQuality = 1.0,
    this.confidenceThreshold = 0.5,
  });

  /// Maps the public Dart API to the Pigeon-generated data classes.
  ScannerOptionsData toData() {
    return ScannerOptionsData(
      scanMode: scanMode.toData(),
      continuous: continuous,
      enableFlash: enableFlash,
      enableGallery: enableGallery,
      enableCameraSwitch: enableCameraSwitch,
      enableBeep: enableBeep,
      enableVibration: enableVibration,
      enableImageCapture: enableImageCapture,
      enableImageAnnotation: enableImageAnnotation,
      allowDuplicate: allowDuplicate,
      duplicateDelay: duplicateDelay,
      scanInterval: scanInterval,
      supportedFormats: supportedFormats.map((f) => f.toData()).toList(),
      scanWindow: scanWindow?.toData(),
      autoZoom: autoZoom,
      imageQuality: imageQuality,
      confidenceThreshold: confidenceThreshold,
    );
  }
}
