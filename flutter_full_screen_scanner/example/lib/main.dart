import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_full_screen_scanner/flutter_full_screen_scanner.dart';
import 'package:image_picker/image_picker.dart';

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
      home: const ScannerScreen(),
    );
  }
}

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final ScannerController _controller = ScannerController();
  final List<ScannerResult> _scannedHistory = [];
  final Map<String, Map<String, dynamic>> _liveBarcodes = {};
  final ImagePicker _picker = ImagePicker();
  ScannerResult? _lastScannedResult;
  DateTime? _lastScanTime;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _scanFromGallery() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      // Pause camera while parsing gallery image
      await _controller.pause();

      final results = await _controller.scanImage(image.path);
      if (results.isNotEmpty && mounted) {
        setState(() {
          _scannedHistory.insertAll(0, results);
          _lastScannedResult = results.first;
          _lastScanTime = DateTime.now();
        });

        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Gallery Scan Success'),
            content: Text('Found ${results.length} barcode(s).'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _controller.resume();
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No barcodes found in image')),
          );
        }
        await _controller.resume();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // The Full Screen Scanner
          FullScreenScanner(
            controller: _controller,
            options: const ScannerOptions(
              allowDuplicate:
                  true, // Set to true so we get continuous frames for the live overlay
              duplicateDelay: 0,
              scanWindow: ScanWindow(
                widthFactor: 0.8,
                heightFactor: 0.3,
              ), // Ultra-wide rectangle
            ),
            onScan: (result) {
              final now = DateTime.now().millisecondsSinceEpoch;
              final nowDateTime = DateTime.now();

              setState(() {
                // Retain imageBytes from previous scan or history if live frame doesn't carry bytes
                final existingBytes = result.imageBytes ??
                    _liveBarcodes[result.value]?['result']?.imageBytes ??
                    _scannedHistory
                        .firstWhere((h) => h.value == result.value,
                            orElse: () => result)
                        .imageBytes ??
                    _lastScannedResult?.imageBytes;

                final finalResult = ScannerResult(
                  value: result.value,
                  type: result.type,
                  imageBytes: existingBytes,
                  corners: result.corners,
                  imageWidth: result.imageWidth,
                  imageHeight: result.imageHeight,
                  timestamp: result.timestamp,
                );

                _liveBarcodes[result.value] = {
                  'result': finalResult,
                  'lastSeen': now,
                };

                // 2-second delay / rate limit for duplicate scans
                if (_lastScanTime == null ||
                    nowDateTime.difference(_lastScanTime!).inMilliseconds >
                        2000 ||
                    _lastScannedResult?.value != finalResult.value) {
                  _lastScannedResult = finalResult;
                  _lastScanTime = nowDateTime;

                  final isDuplicate = _scannedHistory.any(
                    (item) => item.value == finalResult.value,
                  );
                  if (!isDuplicate) {
                    _scannedHistory.insert(0, finalResult);
                  }
                }
              });
            },
            overlayBuilder: (context, state) {
              final now = DateTime.now().millisecondsSinceEpoch;
              // Clean up barcodes not seen in the last 500ms
              _liveBarcodes.removeWhere(
                (key, value) => now - (value['lastSeen'] as int) > 500,
              );

              return Stack(
                children: [
                  Positioned.fill(
                    child: const ScannerCutoutOverlay(
                      scanWindow: ScanWindow(
                        widthFactor: 0.8,
                        heightFactor: 0.3,
                      ),
                      borderColor: Colors.greenAccent,
                      borderWidth: 3.0,
                    ),
                  ),
                  // Draw live barcodes over the camera
                  if (_liveBarcodes.isNotEmpty)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: LiveBarcodeOverlayPainter(
                          liveBarcodes: _liveBarcodes.values
                              .map((e) => e['result'] as ScannerResult)
                              .toList(),
                          history: _scannedHistory,
                        ),
                      ),
                    ),

                  // Flash screen green on successful scan
                  if (state.barcodeDetected)
                    Container(color: Colors.green.withValues(alpha: 0.3)),
                ],
              );
            },
          ),

          // Conditional Live Preview Card below overlay cutout
          if (_lastScannedResult != null)
            Builder(
              builder: (context) {
                final isAlreadyInList = _scannedHistory
                            .where((h) => h.value == _lastScannedResult!.value)
                            .length >
                        1 ||
                    (_scannedHistory
                            .any((h) => h.value == _lastScannedResult!.value) &&
                        _scannedHistory.first.value !=
                            _lastScannedResult!.value);
                return Positioned(
                  bottom: 90,
                  left: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isAlreadyInList
                            ? Colors.amberAccent
                            : Colors.greenAccent,
                        width: 1.5,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black45,
                          blurRadius: 10,
                          spreadRadius: 2,
                        )
                      ],
                    ),
                    child: Row(
                      children: [
                        if (_lastScannedResult!.imageBytes != null)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(
                              width: 48,
                              height: 48,
                              child: Image.memory(
                                _lastScannedResult!.imageBytes!,
                                fit: BoxFit.cover,
                                filterQuality: FilterQuality.high,
                                isAntiAlias: true,
                              ),
                            ),
                          )
                        else
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: Colors.grey[800],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.qr_code,
                                color: isAlreadyInList
                                    ? Colors.amberAccent
                                    : Colors.greenAccent),
                          ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isAlreadyInList
                                          ? Colors.amber.withValues(alpha: 0.2)
                                          : Colors.greenAccent
                                              .withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      isAlreadyInList
                                          ? 'ALREADY IN LIST'
                                          : '✓ SCANNED',
                                      style: TextStyle(
                                        color: isAlreadyInList
                                            ? Colors.amberAccent
                                            : Colors.greenAccent,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _lastScannedResult!.type,
                                    style: TextStyle(
                                        color: Colors.grey[400], fontSize: 11),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _lastScannedResult!.value,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close,
                              color: Colors.grey, size: 20),
                          onPressed: () {
                            setState(() {
                              _lastScannedResult = null;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

          // Top AppBar Controls
          Positioned(
            top: 50,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Scanner SDK',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.photo_library,
                        color: Colors.white,
                        size: 30,
                      ),
                      onPressed: _scanFromGallery,
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.flip_camera_ios,
                        color: Colors.white,
                        size: 30,
                      ),
                      onPressed: _controller.switchCamera,
                    ),
                    IconButton(
                      icon: Icon(
                        _controller.flashEnabled
                            ? Icons.flash_on
                            : Icons.flash_off,
                        color: _controller.flashEnabled
                            ? Colors.yellow
                            : Colors.white,
                        size: 30,
                      ),
                      onPressed: () {
                        _controller.toggleFlash();
                        setState(() {}); // Update icon
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showHistoryBottomSheet,
        backgroundColor: Colors.blueAccent,
        child: const Icon(Icons.history, color: Colors.white),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  void _showHistoryBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'Continuous Scan History',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: _scannedHistory.length,
                itemBuilder: (context, index) {
                  final item = _scannedHistory[index];
                  return Material(
                    color: Colors.transparent,
                    child: ListTile(
                      leading: SizedBox(
                        width: 50,
                        height: 50,
                        child: item.imageBytes != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: CustomPaint(
                                  foregroundPainter: BarcodeLinePainter(
                                    corners: item.corners,
                                    imageWidth:
                                        item.imageWidth?.toDouble() ?? 1080,
                                    imageHeight:
                                        item.imageHeight?.toDouble() ?? 1920,
                                  ),
                                  child: Image.memory(
                                    item.imageBytes!,
                                    fit: BoxFit.contain,
                                    filterQuality: FilterQuality.high,
                                    isAntiAlias: true,
                                  ),
                                ),
                              )
                            : Container(
                                color: Colors.grey[800],
                                child: const Icon(
                                  Icons.qr_code,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                      title: Text(
                        item.value,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        'Type: ${item.type}',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                      onTap: () {
                        if (item.imageBytes != null) {
                          showDialog(
                            context: context,
                            builder: (context) {
                              return Dialog(
                                backgroundColor: Colors.transparent,
                                child: Stack(
                                  alignment: Alignment.topRight,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: AspectRatio(
                                        aspectRatio: (item.imageWidth ?? 1) /
                                            (item.imageHeight ?? 1),
                                        child: CustomPaint(
                                          foregroundPainter: BarcodeLinePainter(
                                            corners: item.corners,
                                            imageWidth:
                                                item.imageWidth?.toDouble() ??
                                                    1080,
                                            imageHeight:
                                                item.imageHeight?.toDouble() ??
                                                    1920,
                                          ),
                                          child: Image.memory(
                                            item.imageBytes!,
                                            fit: BoxFit.contain,
                                            filterQuality: FilterQuality.high,
                                            isAntiAlias: true,
                                          ),
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.close,
                                        color: Colors.white,
                                        size: 30,
                                      ),
                                      onPressed: () => Navigator.pop(context),
                                    ),
                                  ],
                                ),
                              );
                            },
                          );
                        }
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class LiveBarcodeOverlayPainter extends CustomPainter {
  final List<ScannerResult> liveBarcodes;
  final List<ScannerResult> history;

  LiveBarcodeOverlayPainter({
    required this.liveBarcodes,
    required this.history,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final barcode in liveBarcodes) {
      if (barcode.corners == null || barcode.corners!.isEmpty) continue;

      final imageWidth = barcode.imageWidth?.toDouble() ?? 1080;
      final imageHeight = barcode.imageHeight?.toDouble() ?? 1920;

      // Calculate BoxFit.cover scaling math to map coordinates to screen
      final scaleX = size.width / imageWidth;
      final scaleY = size.height / imageHeight;
      final scale = scaleX > scaleY ? scaleX : scaleY;

      final dxOffset = (imageWidth * scale - size.width) / 2;
      final dyOffset = (imageHeight * scale - size.height) / 2;

      // Find the center of the barcode
      double centerX = 0;
      double centerY = 0;
      for (final corner in barcode.corners!) {
        centerX += (corner.x * scale) - dxOffset;
        centerY += (corner.y * scale) - dyOffset;
      }
      centerX /= barcode.corners!.length;
      centerY /= barcode.corners!.length;

      // Check if already in history
      final inHistory = history.any((h) => h.value == barcode.value);

      if (inHistory) {
        final textSpan = TextSpan(
          text: '✓ Scanned: ${barcode.value}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        );

        final textPainter = TextPainter(
          text: textSpan,
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
        );

        textPainter.layout();
        final bgRect = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(centerX, centerY),
            width: textPainter.width + 16,
            height: textPainter.height + 10,
          ),
          const Radius.circular(8),
        );
        final bgPaint = Paint()
          ..color = const Color(0xE62E7D32); // Vibrant dark green with opacity
        canvas.drawRRect(bgRect, bgPaint);

        textPainter.paint(
          canvas,
          Offset(
            centerX - textPainter.width / 2,
            centerY - textPainter.height / 2,
          ),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant LiveBarcodeOverlayPainter oldDelegate) {
    return true;
  }
}

class BarcodeLinePainter extends CustomPainter {
  final List<Point>? corners;
  final double imageWidth;
  final double imageHeight;

  BarcodeLinePainter({
    required this.corners,
    required this.imageWidth,
    required this.imageHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (corners == null || corners!.length < 4) return;

    final paint = Paint()
      ..color = Colors.greenAccent
      ..strokeWidth = 1.5
      ..isAntiAlias = true
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Calculate exact BoxFit.contain scaling and translation offsets (dx, dy)
    final scale = math.min(
      size.width / imageWidth,
      size.height / imageHeight,
    );
    final dx = (size.width - imageWidth * scale) / 2;
    final dy = (size.height - imageHeight * scale) / 2;

    final rawPoints = corners!
        .map((c) => Offset(c.x * scale + dx, c.y * scale + dy))
        .toList();

    final linePoints = _calculateCenterLine(rawPoints);
    if (linePoints.length == 2) {
      canvas.drawLine(linePoints[0], linePoints[1], paint);
    }
  }

  List<Offset> _calculateCenterLine(List<Offset> corners) {
    if (corners.isEmpty) {
      return [Offset.zero, Offset.zero];
    }
    if (corners.length < 4) {
      double minX = corners.first.dx, maxX = corners.first.dx;
      double minY = corners.first.dy, maxY = corners.first.dy;
      for (final p in corners) {
        if (p.dx < minX) minX = p.dx;
        if (p.dx > maxX) maxX = p.dx;
        if (p.dy < minY) minY = p.dy;
        if (p.dy > maxY) maxY = p.dy;
      }
      final w = maxX - minX;
      final h = maxY - minY;
      final cx = (minX + maxX) / 2.0;
      final cy = (minY + maxY) / 2.0;
      if (w >= h) {
        return [Offset(minX, cy), Offset(maxX, cy)];
      } else {
        return [Offset(cx, minY), Offset(cx, maxY)];
      }
    }

    // Calculate centroid
    double cx = 0;
    double cy = 0;
    for (final p in corners) {
      cx += p.dx;
      cy += p.dy;
    }
    cx /= 4.0;
    cy /= 4.0;

    // Sort corners clockwise around centroid
    final sorted = List<Offset>.from(corners);
    sorted.sort((a, b) {
      final angleA = math.atan2(a.dy - cy, a.dx - cx);
      final angleB = math.atan2(b.dy - cy, b.dx - cx);
      return angleA.compareTo(angleB);
    });

    final q0 = sorted[0];
    final q1 = sorted[1];
    final q2 = sorted[2];
    final q3 = sorted[3];

    // Compute side lengths
    final d0 = (q0 - q1).distance;
    final d1 = (q1 - q2).distance;
    final d2 = (q2 - q3).distance;
    final d3 = (q3 - q0).distance;

    // Compare opposite pairs of sides to find short vs long
    final sum02 = d0 + d2;
    final sum13 = d1 + d3;

    if (sum02 > sum13) {
      // q0-q1 and q2-q3 are long edges, q1-q2 and q3-q0 are short edges.
      final mid12 = Offset((q1.dx + q2.dx) / 2.0, (q1.dy + q2.dy) / 2.0);
      final mid30 = Offset((q3.dx + q0.dx) / 2.0, (q3.dy + q0.dy) / 2.0);
      return [mid12, mid30];
    } else {
      // q1-q2 and q3-q0 are long edges, q0-q1 and q2-q3 are short edges.
      final mid01 = Offset((q0.dx + q1.dx) / 2.0, (q0.dy + q1.dy) / 2.0);
      final mid23 = Offset((q2.dx + q3.dx) / 2.0, (q2.dy + q3.dy) / 2.0);
      return [mid01, mid23];
    }
  }

  @override
  bool shouldRepaint(covariant BarcodeLinePainter oldDelegate) {
    return oldDelegate.corners != corners;
  }
}
