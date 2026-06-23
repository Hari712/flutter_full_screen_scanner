import 'package:flutter/material.dart';

import 'image_processor.dart';
import 'scanner_controller.dart';
import 'scanner_models.dart';
import 'scanner_options.dart';
import 'scanner_view.dart';

/// The main public widget for the Full Screen Scanner.
class FullScreenScanner extends StatefulWidget {
  /// The controller used to programmatically interact with the scanner.
  final ScannerController controller;

  /// Configuration options for the scanner.
  final ScannerOptions options;

  /// Callback triggered when a barcode is successfully scanned.
  final void Function(ScannerResult result)? onScan;

  /// Custom builder for overlaying UI on top of the camera feed.
  final Widget Function(BuildContext context, ScannerState state)?
  overlayBuilder;

  const FullScreenScanner({
    super.key,
    required this.controller,
    required this.options,
    this.onScan,
    this.overlayBuilder,
  });

  @override
  State<FullScreenScanner> createState() => _FullScreenScannerState();
}

class _FullScreenScannerState extends State<FullScreenScanner> {
  late ScannerState _currentState;

  @override
  void initState() {
    super.initState();
    _currentState = ScannerState(
      scanning: widget.controller.isScanning,
      flashEnabled: widget.controller.flashEnabled,
    );

    widget.controller.events.listen(_onScannerEvent);
    widget.controller.addListener(_onControllerStateChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerStateChanged);
    super.dispose();
  }

  void _onControllerStateChanged() {
    if (mounted) {
      setState(() {
        _currentState = _currentState.copyWith(
          scanning: widget.controller.isScanning && !widget.controller.isPaused,
          flashEnabled: widget.controller.flashEnabled,
        );
      });
    }
  }

  void _onScannerEvent(ScannerEvent event) async {
    if (!mounted) return;

    if (event.type == ScannerEventType.scanned) {
      ScannerResult result = event.data as ScannerResult;

      setState(() {
        _currentState = _currentState.copyWith(
          barcodeDetected: true,
          capturing:
              widget.options.enableImageCapture &&
              widget.options.enableImageAnnotation,
          currentDetectedBarcodes: [result],
        );
      });

      // Handle Image Annotation in background isolate
      if (widget.options.enableImageCapture &&
          widget.options.enableImageAnnotation &&
          result.imageBytes != null &&
          result.corners != null &&
          result.corners!.isNotEmpty) {
        final annotatedBytes = await ImageProcessor.annotateImage(
          result.imageBytes!,
          result.corners!,
        );
        if (annotatedBytes != null) {
          result = ScannerResult(
            value: result.value,
            type: result.type,
            imageBytes: annotatedBytes,
            corners: result.corners,
            imageWidth: result.imageWidth,
            imageHeight: result.imageHeight,
            timestamp: result.timestamp,
          );
        }
      }

      if (!mounted) return;

      if (widget.onScan != null) {
        widget.onScan!(result);
      }

      // Briefly reset detection state to allow UI flashes/animations
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          setState(() {
            _currentState = _currentState.copyWith(
              barcodeDetected: false,
              currentDetectedBarcodes: [],
            );
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // The underlying native camera preview
        ScannerView(controller: widget.controller, options: widget.options),

        // The custom overlay builder
        if (widget.overlayBuilder != null)
          Positioned.fill(
            child: widget.overlayBuilder!(context, _currentState),
          ),
      ],
    );
  }
}
