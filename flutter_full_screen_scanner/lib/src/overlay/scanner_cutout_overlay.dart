import 'package:flutter/material.dart';
import '../scanner_options.dart';

/// A helper widget that draws a darkened overlay with a clear cutout area.
/// This visually represents the active [ScanWindow].
///
/// Note: This is an optional UI component. As per requirements, the core SDK
/// does not hardcode any UI, allowing full customizability via the overlayBuilder.
class ScannerCutoutOverlay extends StatelessWidget {
  /// The dimensions of the cutout window, defined as percentages of the screen.
  final ScanWindow scanWindow;

  /// The color of the darkened background outside the cutout.
  final Color overlayColor;

  /// The color of the border drawn around the cutout hole.
  final Color borderColor;

  /// The width of the border around the cutout.
  final double borderWidth;

  /// The border radius for the corners of the cutout.
  final double borderRadius;

  const ScannerCutoutOverlay({
    super.key,
    required this.scanWindow,
    this.overlayColor = const Color(0x88000000), // Semi-transparent black
    this.borderColor = Colors.white,
    this.borderWidth = 2.0,
    this.borderRadius = 12.0,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cutoutWidth = constraints.maxWidth * scanWindow.widthFactor;
        final cutoutHeight = constraints.maxHeight * scanWindow.heightFactor;

        return CustomPaint(
          size: Size(constraints.maxWidth, constraints.maxHeight),
          painter: _CutoutPainter(
            cutoutWidth: cutoutWidth,
            cutoutHeight: cutoutHeight,
            overlayColor: overlayColor,
            borderColor: borderColor,
            borderWidth: borderWidth,
            borderRadius: borderRadius,
          ),
        );
      },
    );
  }
}

class _CutoutPainter extends CustomPainter {
  final double cutoutWidth;
  final double cutoutHeight;
  final Color overlayColor;
  final Color borderColor;
  final double borderWidth;
  final double borderRadius;

  _CutoutPainter({
    required this.cutoutWidth,
    required this.cutoutHeight,
    required this.overlayColor,
    required this.borderColor,
    required this.borderWidth,
    required this.borderRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);

    final cutoutRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: cutoutWidth,
      height: cutoutHeight,
    );

    final backgroundPaint = Paint()..color = overlayColor;

    // Create the background path covering the whole screen
    final backgroundPath = Path()..addRect(rect);

    // Create the cutout path
    final cutoutPath = Path()
      ..addRRect(
        RRect.fromRectAndRadius(cutoutRect, Radius.circular(borderRadius)),
      );

    // Subtract the cutout from the background using difference
    final overlayPath = Path.combine(
      PathOperation.difference,
      backgroundPath,
      cutoutPath,
    );

    canvas.drawPath(overlayPath, backgroundPaint);

    // Draw the active border line around the hole
    if (borderWidth > 0) {
      final borderPaint = Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth;

      canvas.drawRRect(
        RRect.fromRectAndRadius(cutoutRect, Radius.circular(borderRadius)),
        borderPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CutoutPainter oldDelegate) {
    return oldDelegate.cutoutWidth != cutoutWidth ||
        oldDelegate.cutoutHeight != cutoutHeight ||
        oldDelegate.overlayColor != overlayColor ||
        oldDelegate.borderColor != borderColor ||
        oldDelegate.borderWidth != borderWidth ||
        oldDelegate.borderRadius != borderRadius;
  }
}
