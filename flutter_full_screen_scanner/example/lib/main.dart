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
              setState(() {
                _liveBarcodes[result.value] = {
                  'result': result,
                  'lastSeen': now,
                };

                // Add to history only if it's new
                final isDuplicate = _scannedHistory.any(
                  (item) => item.value == result.value,
                );
                if (!isDuplicate) {
                  _scannedHistory.insert(0, result);
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
                                child: AspectRatio(
                                  aspectRatio:
                                      (item.imageWidth ?? 1) /
                                      (item.imageHeight ?? 1),
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
                                    ),
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
                                        aspectRatio:
                                            (item.imageWidth ?? 1) /
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
          text: '${barcode.value}\n(already scanned)',
          style: const TextStyle(
            color: Colors.redAccent,
            fontSize: 16,
            fontWeight: FontWeight.bold,
            backgroundColor: Colors.black54,
          ),
        );

        final textPainter = TextPainter(
          text: textSpan,
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
        );

        textPainter.layout();
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
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    // Scale factors to map native image coordinates to the Flutter widget size
    final scaleX = size.width / imageWidth;
    final scaleY = size.height / imageHeight;

    // We assume corners are ordered: top-left, top-right, bottom-right, bottom-left
    // (This is standard for both ML Kit and Vision bounding boxes)
    final p0 = Offset(corners![0].x * scaleX, corners![0].y * scaleY);
    final p1 = Offset(corners![1].x * scaleX, corners![1].y * scaleY);
    final p2 = Offset(corners![2].x * scaleX, corners![2].y * scaleY);
    final p3 = Offset(corners![3].x * scaleX, corners![3].y * scaleY);

    // Calculate edge lengths to determine orientation (vertical vs horizontal vs diagonal)
    // corners are guaranteed to be in clockwise order starting from top-left (relative to the barcode).
    final dist01 = (p0 - p1).distance;
    final dist12 = (p1 - p2).distance;

    Offset start, end;
    if (dist01 > dist12) {
      // 0-1 and 2-3 are the long edges. 1-2 and 3-0 are the short edges.
      // Connect midpoints of the short edges to draw the line parallel to the long edges.
      start = Offset((p3.dx + p0.dx) / 2, (p3.dy + p0.dy) / 2);
      end = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
    } else {
      // 1-2 and 3-0 are the long edges. 0-1 and 2-3 are the short edges.
      // Connect midpoints of the short edges.
      start = Offset((p0.dx + p1.dx) / 2, (p0.dy + p1.dy) / 2);
      end = Offset((p2.dx + p3.dx) / 2, (p2.dy + p3.dy) / 2);
    }

    canvas.drawLine(start, end, paint);
  }

  @override
  bool shouldRepaint(covariant BarcodeLinePainter oldDelegate) {
    return oldDelegate.corners != corners;
  }
}
