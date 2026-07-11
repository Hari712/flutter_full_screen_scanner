import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'scanner_controller.dart';
import 'scanner_options.dart';

/// The native platform view that renders the camera feed.
/// It wraps AndroidView and UiKitView to display the native scanner.
class ScannerView extends StatefulWidget {
  final ScannerController controller;
  final ScannerOptions options;
  final void Function()? onPlatformViewCreated;

  const ScannerView({
    super.key,
    required this.controller,
    required this.options,
    this.onPlatformViewCreated,
  });

  @override
  State<ScannerView> createState() => _ScannerViewState();
}

class _ScannerViewState extends State<ScannerView> {
  static const String _viewType = 'flutter_full_screen_scanner_view';

  @override
  Widget build(BuildContext context) {
    // Pass creation parameters to configure the native platform view.
    // For example, duplicate prevention configuration.
    final Map<String, dynamic> creationParams = {
      'allowDuplicate': widget.options.allowDuplicate,
      'duplicateDelay': widget.options.duplicateDelay,
      'enableImageCapture': widget.options.enableImageCapture,
      if (widget.options.scanWindow != null) ...{
        'scanWindowWidthFactor': widget.options.scanWindow!.widthFactor,
        'scanWindowHeightFactor': widget.options.scanWindow!.heightFactor,
      },
    };

    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidView(
        viewType: _viewType,
        layoutDirection: TextDirection.ltr,
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _onPlatformViewCreated,
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      return UiKitView(
        viewType: _viewType,
        layoutDirection: TextDirection.ltr,
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _onPlatformViewCreated,
      );
    }

    return const Center(child: Text('Platform not supported for scanner'));
  }

  void _onPlatformViewCreated(int id) {
    widget.controller.internalSetScanning(true);
    if (widget.onPlatformViewCreated != null) {
      widget.onPlatformViewCreated!();
    }
  }
}
