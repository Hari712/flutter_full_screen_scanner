import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_full_screen_scanner/flutter_full_screen_scanner.dart'
    as fss;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Scanner Demo',
      theme: ThemeData.dark(useMaterial3: true),
      home: const FullScreenScannerPage(),
    );
  }
}

enum ScanMode { barcode, qr }

class FullScreenScannerPage extends StatefulWidget {
  const FullScreenScannerPage({super.key});

  @override
  State<FullScreenScannerPage> createState() => _FullScreenScannerPageState();
}

class _FullScreenScannerPageState extends State<FullScreenScannerPage>
    with WidgetsBindingObserver {
  late final fss.ScannerController _fssController;
  StreamSubscription? _fssSubscription;

  ScanMode _scanMode = ScanMode.barcode;
  bool _isCapturing = false;

  final List<String> _scannedHistory = [];
  List<String> _currentDetectedBarcodes = [];
  List<String> _duplicateBarcodes = [];

  int _scanCountdown = 0;
  Timer? _countdownTimer;
  Timer? _clearDuplicateTimer;

  bool _isBarcodeDetectedInWindow = false;
  final Map<String, DateTime> _lastDuplicateToastTimes = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _fssController = fss.ScannerController();
    _fssSubscription = _fssController.events.listen((event) {
      if (event.type == fss.ScannerEventType.scanned) {
        final result = event.data as fss.ScannerResult;
        _handleFssScanResult(result);
      }
    });
  }

  void _handleFssScanResult(fss.ScannerResult result) async {
    debugPrint("[Dart Received] value: ${result.value}, type: ${result.type}");
    if (_isCapturing) {
      debugPrint("[Dart Skipped] reason: isCapturing active");
      return;
    }

    final String rawCode = result.value;
    final String code = _sanitizeBarcode(rawCode);
    if (code.isEmpty) {
      debugPrint("[Dart Skipped] reason: sanitized code is empty");
      return;
    }

    // Filter based on scan mode
    final isQr = result.type.toLowerCase().contains('qr');
    if (_scanMode == ScanMode.qr && !isQr) {
      debugPrint(
          "[Dart Skipped] reason: scanMode mismatch (expected QR, got non-QR)");
      return;
    }
    if (_scanMode == ScanMode.barcode && isQr) {
      debugPrint(
          "[Dart Skipped] reason: scanMode mismatch (expected Barcode, got QR)");
      return;
    }

    // Filter by scan window in Dart using the exact CustomPainter coordinate mapping
    final corners = result.corners;
    if (corners != null && corners.length >= 4) {
      final screenWidth = MediaQuery.of(context).size.width;
      final screenHeight = MediaQuery.of(context).size.height;
      final isBarcodeMode = _scanMode == ScanMode.barcode;
      final boxWidth =
          isBarcodeMode ? (screenWidth * 0.70) : (screenWidth * 0.50);
      final boxHeight = isBarcodeMode ? 60.0 : (screenWidth * 0.50);

      final left = (screenWidth - boxWidth) / 2;
      final right = (screenWidth + boxWidth) / 2;
      final top = (screenHeight - boxHeight) / 2;
      final bottom = (screenHeight + boxHeight) / 2;

      final imageWidth = result.imageWidth?.toDouble() ?? 1080.0;
      final imageHeight = result.imageHeight?.toDouble() ?? 1920.0;

      final scaleX = screenWidth / imageWidth;
      final scaleY = screenHeight / imageHeight;
      final scale = scaleX > scaleY ? scaleX : scaleY;

      final dxOffset = (imageWidth * scale - screenWidth) / 2;
      final dyOffset = (imageHeight * scale - screenHeight) / 2;

      double sumX = 0;
      double sumY = 0;
      for (final pt in corners) {
        sumX += pt.x * scale - dxOffset;
        sumY += pt.y * scale - dyOffset;
      }

      final centroidX = sumX / corners.length;
      final centroidY = sumY / corners.length;

      debugPrint(
          "[Dart Centroid] centroidX: $centroidX, centroidY: $centroidY | box bounds: X [$left .. $right], Y [$top .. $bottom]");

      // 1. Ensure barcode is not cut off by screen boundaries (at least 5px margin)
      final screenMargin = 5.0;
      for (final pt in corners) {
        final px = pt.x * scale - dxOffset;
        final py = pt.y * scale - dyOffset;
        if (px < screenMargin ||
            px > screenWidth - screenMargin ||
            py < screenMargin ||
            py > screenHeight - screenMargin) {
          debugPrint("[Dart Skipped] reason: barcode cut off by screen edges");
          return;
        }
      }

      // 2. Ensure the barcode center (centroid) is inside the scan window vertically
      if (centroidY < top || centroidY > bottom) {
        debugPrint(
            "[Dart Skipped] reason: barcode center outside scan window vertically");
        return;
      }

      // 3. Ensure centroid is inside the scan window horizontally
      if (centroidX < left || centroidX > right) {
        debugPrint(
            "[Dart Skipped] reason: barcode center outside scan window horizontally");
        return;
      }
    } else {
      debugPrint(
          "[Dart Skipped] reason: corners count < 4 or null (${corners?.length})");
    }

    if (_scannedHistory.contains(code)) {
      debugPrint("[Dart Skipped] reason: duplicate barcode in history: $code");
      _showDuplicateToast(code);
      return;
    }

    try {
      _isCapturing = true;

      setState(() {
        _currentDetectedBarcodes = [code];
        _duplicateBarcodes = [];
        _isBarcodeDetectedInWindow = true;
        _scanCountdown = 2; // 2 seconds cooldown
        _scannedHistory.insert(0, code);
      });

      // Start 2-second countdown timer. Scanner is locked during this period
      _countdownTimer?.cancel();
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() {
          if (_scanCountdown > 1) {
            _scanCountdown--;
          } else {
            _scanCountdown = 0;
            _isCapturing = false;
            _currentDetectedBarcodes = [];
            _isBarcodeDetectedInWindow = false;
            timer.cancel();
          }
        });
      });
    } catch (e) {
      debugPrint("Error in _handleFssScanResult: $e");
      setState(() {
        _isCapturing = false;
        _isBarcodeDetectedInWindow = false;
        _scanCountdown = 0;
      });
    }
  }

  void _showDuplicateToast(String code) {
    final now = DateTime.now();
    final lastSeen = _lastDuplicateToastTimes[code];
    if (lastSeen != null &&
        now.difference(lastSeen) < const Duration(seconds: 2)) {
      return;
    }
    _lastDuplicateToastTimes[code] = now;

    _clearDuplicateTimer?.cancel();
    _clearDuplicateTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _duplicateBarcodes = [];
        });
      }
    });

    if (!_duplicateBarcodes.contains(code)) {
      setState(() {
        _duplicateBarcodes = [code];
        _currentDetectedBarcodes = [];
        _isBarcodeDetectedInWindow = false;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _fssSubscription?.cancel();
    _fssController.dispose();
    _countdownTimer?.cancel();
    _clearDuplicateTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _fssController.pause();
    } else if (state == AppLifecycleState.resumed) {
      _fssController.resume();
    }
  }

  void _showToast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _showScannedHistory(BuildContext context) async {
    try {
      _fssController.pause();
    } catch (e) {
      debugPrint("Error pausing scanner: $e");
    }

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  const Icon(Icons.history, color: Colors.blueAccent),
                  const SizedBox(width: 10),
                  Text(
                    "Scanned History (${_scannedHistory.length})",
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.blueAccent),
                  ),
                ],
              ),
            ),
            if (_scannedHistory.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Text("No barcodes scanned yet",
                    style: TextStyle(color: Colors.grey)),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.4),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  itemCount: _scannedHistory.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (context, index) {
                    final sn = _scannedHistory[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.qr_code_2, color: Colors.green),
                      title: Text(sn,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.black)),
                      trailing: const Icon(Icons.check_circle,
                          color: Colors.green, size: 20),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );

    try {
      _fssController.resume();
    } catch (e) {
      debugPrint("Error resuming scanner: $e");
    }
  }

  Future<void> _pickAndScanImage() async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);
      if (pickedFile == null) return;

      final results = await _fssController.scanImage(pickedFile.path);
      if (results.isNotEmpty) {
        final decodedValues = <String>{};
        for (final r in results) {
          final rawValue = _sanitizeBarcode(r.value);
          if (rawValue.isNotEmpty) {
            decodedValues.add(rawValue);
          }
        }

        if (decodedValues.isNotEmpty) {
          if (!mounted) return;

          await showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text("Detected Barcodes (${decodedValues.length})",
                  style: const TextStyle(color: Colors.black)),
              backgroundColor: Colors.white,
              content: SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: decodedValues.length,
                  itemBuilder: (ctx, index) {
                    final val = decodedValues.elementAt(index);
                    final isAlreadyScanned = _scannedHistory.contains(val);
                    return ListTile(
                      title: Text(val,
                          style: TextStyle(
                            color: isAlreadyScanned ? Colors.red : Colors.black,
                            decoration: isAlreadyScanned
                                ? TextDecoration.lineThrough
                                : null,
                          )),
                      subtitle: isAlreadyScanned
                          ? const Text("Already Scanned",
                              style: TextStyle(color: Colors.red))
                          : null,
                      onTap: isAlreadyScanned
                          ? null
                          : () {
                              Navigator.pop(ctx);
                              setState(() {
                                _scannedHistory.insert(0, val);
                                _currentDetectedBarcodes = [val];
                                _duplicateBarcodes = [];
                                _isBarcodeDetectedInWindow = true;
                                _scanCountdown = 2;
                              });

                              _countdownTimer?.cancel();
                              _countdownTimer = Timer.periodic(
                                  const Duration(seconds: 1), (timer) {
                                if (!mounted) {
                                  timer.cancel();
                                  return;
                                }
                                setState(() {
                                  if (_scanCountdown > 1) {
                                    _scanCountdown--;
                                  } else {
                                    _scanCountdown = 0;
                                    _isCapturing = false;
                                    _currentDetectedBarcodes = [];
                                    _isBarcodeDetectedInWindow = false;
                                    timer.cancel();
                                  }
                                });
                              });
                            },
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text("Cancel",
                        style: TextStyle(color: Colors.blueAccent)))
              ],
            ),
          );
        } else {
          _showToast("No text found in barcodes.");
        }
      } else {
        _showToast("No barcodes detected in image.");
      }
    } catch (e) {
      debugPrint("Gallery scan error: $e");
      if (mounted) {
        _showToast("Error scanning image: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final screenWidth = constraints.maxWidth;
          final screenHeight = constraints.maxHeight;
          final isBarcodeMode = _scanMode == ScanMode.barcode;

          // Small scan window box
          final boxWidth =
              isBarcodeMode ? screenWidth * 0.70 : screenWidth * 0.50;
          final boxHeight = isBarcodeMode ? 60.0 : screenWidth * 0.50;

          final scanWindowRect = Rect.fromCenter(
            center: Offset(screenWidth / 2, screenHeight / 2),
            width: boxWidth,
            height: boxHeight,
          );

          return Stack(
            children: [
              Positioned.fill(
                child: fss.ScannerView(
                  controller: _fssController,
                  options: fss.ScannerOptions(
                    allowDuplicate: false,
                    duplicateDelay: 2000,
                    enableImageCapture: true,
                    scanMode: _scanMode == ScanMode.qr
                        ? fss.ScanMode.qr
                        : fss.ScanMode.barcode,
                    supportedFormats: _scanMode == ScanMode.qr
                        ? const [fss.BarcodeFormat.qrCode]
                        : const [
                            fss.BarcodeFormat.code128,
                            fss.BarcodeFormat.code39,
                            fss.BarcodeFormat.code93,
                            fss.BarcodeFormat.codaBar,
                            fss.BarcodeFormat.dataMatrix,
                            fss.BarcodeFormat.ean13,
                            fss.BarcodeFormat.ean8,
                            fss.BarcodeFormat.itf,
                            fss.BarcodeFormat.upcA,
                            fss.BarcodeFormat.upcE,
                            fss.BarcodeFormat.pdf417,
                            fss.BarcodeFormat.aztec,
                          ],
                    scanWindow: fss.ScanWindow(
                      widthFactor: isBarcodeMode ? 0.70 : 0.50,
                      heightFactor: isBarcodeMode ? 60.0 / screenHeight : 0.50,
                    ),
                  ),
                ),
              ),
              // Dark Overlay with hole
              CustomPaint(
                size: Size(screenWidth, screenHeight),
                painter: ScannerOverlayPainter(scanWindow: scanWindowRect),
              ),
              // Center Scan Window
              Center(
                child: Container(
                  width: boxWidth,
                  height: boxHeight,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _isBarcodeDetectedInWindow
                          ? Colors.greenAccent
                          : Colors.orange,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Container(
                      width: boxWidth * 0.3,
                      height: 2,
                      decoration: BoxDecoration(
                        color: _isBarcodeDetectedInWindow
                            ? Colors.greenAccent
                            : Colors.orange,
                        borderRadius: BorderRadius.circular(1),
                        boxShadow: [
                          BoxShadow(
                            color: (_isBarcodeDetectedInWindow
                                    ? Colors.greenAccent
                                    : Colors.orange)
                                .withAlpha(128),
                            blurRadius: 4,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // Message and Icon
              Positioned(
                top: (screenHeight / 2) - (boxHeight / 2) - 60,
                left: 20,
                right: 20,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.pan_tool,
                      color: _isBarcodeDetectedInWindow
                          ? Colors.greenAccent
                          : Colors.orange,
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        "Please keep one hand distance between barcode / QR",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _isBarcodeDetectedInWindow
                              ? Colors.greenAccent
                              : Colors.orange,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Mode Selector (Barcode / QR) & Controls Top Bar
              Positioned(
                top: MediaQuery.of(context).padding.top + 10,
                left: 20,
                right: 20,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Clear History Button
                    CircleAvatar(
                      backgroundColor: Colors.black45,
                      child: IconButton(
                        icon: const Icon(Icons.refresh, color: Colors.white),
                        onPressed: () {
                          setState(() {
                            _scannedHistory.clear();
                          });
                          _showToast("History cleared.");
                        },
                      ),
                    ),
                    // Mode Selector Pill
                    Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white24),
                      ),
                      padding: const EdgeInsets.all(2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GestureDetector(
                            onTap: () =>
                                setState(() => _scanMode = ScanMode.barcode),
                            child: Container(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              decoration: BoxDecoration(
                                color: _scanMode == ScanMode.barcode
                                    ? Colors.orange
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              alignment: Alignment.center,
                              child: const Text(
                                "Barcode",
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13),
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: () =>
                                setState(() => _scanMode = ScanMode.qr),
                            child: Container(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              decoration: BoxDecoration(
                                color: _scanMode == ScanMode.qr
                                    ? Colors.orange
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              alignment: Alignment.center,
                              child: const Text(
                                "QR Code",
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Right controls (Flip Camera & Flash)
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: Colors.black45,
                          child: IconButton(
                            icon: const Icon(Icons.flip_camera_ios,
                                color: Colors.white),
                            onPressed: () async {
                              await _fssController.switchCamera();
                              setState(() {});
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        CircleAvatar(
                          backgroundColor: Colors.black45,
                          child: IconButton(
                            icon: Icon(
                              _fssController.flashEnabled
                                  ? Icons.flash_on
                                  : Icons.flash_off,
                              color: _fssController.flashEnabled
                                  ? Colors.yellow
                                  : Colors.white,
                            ),
                            onPressed: () async {
                              await _fssController.toggleFlash();
                              setState(() {});
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Bottom Buttons
              Positioned(
                bottom: 30,
                left: 20,
                child: CircleAvatar(
                  backgroundColor: Colors.black45,
                  radius: 25,
                  child: IconButton(
                    icon: const Icon(Icons.list_alt, color: Colors.white),
                    onPressed: () => _showScannedHistory(context),
                  ),
                ),
              ),
              Positioned(
                bottom: 30,
                right: 20,
                child: CircleAvatar(
                  backgroundColor: Colors.black45,
                  radius: 25,
                  child: IconButton(
                    icon: const Icon(Icons.photo_library, color: Colors.white),
                    onPressed: () => _pickAndScanImage(),
                  ),
                ),
              ),
              // Cooldown Indicator
              if (_scanCountdown > 0)
                Positioned(
                  top: (screenHeight / 2) - (boxHeight / 2) - 140,
                  left: 30,
                  right: 30,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.greenAccent, width: 2),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.check_circle,
                              color: Colors.greenAccent, size: 24),
                          const SizedBox(width: 10),
                          Text(
                            "SCANNED! Next scan in ${_scanCountdown}s",
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              // Scan result view
              if (_currentDetectedBarcodes.isNotEmpty ||
                  _duplicateBarcodes.isNotEmpty)
                Positioned(
                  top: (screenHeight / 2) + (boxHeight / 2) + 30,
                  left: 30,
                  right: 30,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _duplicateBarcodes.isNotEmpty
                              ? Colors.redAccent
                              : Colors.greenAccent,
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_duplicateBarcodes.isNotEmpty) ...[
                            Text(
                              _duplicateBarcodes
                                  .map((s) => "$s\n(ALREADY SCANNED)")
                                  .join('\n'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.redAccent,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ],
                          if (_duplicateBarcodes.isNotEmpty &&
                              _currentDetectedBarcodes.isNotEmpty)
                            const SizedBox(height: 6),
                          if (_currentDetectedBarcodes.isNotEmpty) ...[
                            Text(
                              _currentDetectedBarcodes.join('\n'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.greenAccent,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class ScannerOverlayPainter extends CustomPainter {
  final Rect scanWindow;
  final double borderRadius;

  ScannerOverlayPainter({required this.scanWindow, this.borderRadius = 12.0});

  @override
  void paint(Canvas canvas, Size size) {
    final backgroundPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final holePath = Path()
      ..addRRect(
          RRect.fromRectAndRadius(scanWindow, Radius.circular(borderRadius)));

    final path =
        Path.combine(PathOperation.difference, backgroundPath, holePath);

    final paint = Paint()
      ..color = Colors.black.withAlpha(128)
      ..style = PaintingStyle.fill;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant ScannerOverlayPainter oldDelegate) {
    return oldDelegate.scanWindow != scanWindow ||
        oldDelegate.borderRadius != borderRadius;
  }
}

String _sanitizeBarcode(String raw) {
  if (raw.isEmpty) return raw;

  if (raw.startsWith(']')) {
    final match = RegExp(r'^\][a-zA-Z0-9]{1,2}').firstMatch(raw);
    if (match != null) {
      raw = raw.substring(match.end);
    }
  }

  raw = raw.replaceFirst(RegExp(r'^[^a-zA-Z0-9]+'), '');
  return raw;
}
