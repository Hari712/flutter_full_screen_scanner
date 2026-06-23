# Examples

## Basic Continuous Scanning
```dart
import 'package:flutter/material.dart';
import 'package:flutter_full_screen_scanner/flutter_full_screen_scanner.dart';

class BasicScanner extends StatefulWidget {
  @override
  State<BasicScanner> createState() => _BasicScannerState();
}

class _BasicScannerState extends State<BasicScanner> {
  final ScannerController _controller = ScannerController();
  String lastScan = "";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          FullScreenScanner(
            controller: _controller,
            options: const ScannerOptions(
              allowDuplicate: false,
              duplicateDelay: 1500,
            ),
            onScan: (result) {
              setState(() {
                lastScan = result.value;
              });
            },
            overlayBuilder: (context, state) {
              return ScannerCutoutOverlay(
                borderColor: state.barcodeDetected ? Colors.green : Colors.white,
              );
            },
          ),
          Positioned(
            bottom: 50,
            left: 20,
            child: Text(
              "Last Scan: $lastScan",
              style: TextStyle(color: Colors.white, fontSize: 24),
            ),
          )
        ],
      ),
    );
  }
}
```
