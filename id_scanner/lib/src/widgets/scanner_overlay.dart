import 'package:flutter/material.dart';

/// A [CustomPainter] that dims the area outside a given [frameRect],
/// creating the classic "scan window" darkened-surround effect.
class ScannerOverlayPainter extends CustomPainter {
  const ScannerOverlayPainter({
    required this.frameRect,
    this.overlayColor = const Color(0x73000000),
  });

  /// The rectangle that remains transparent (the scan window).
  final Rect frameRect;

  /// The colour used to dim the surrounding area. Defaults to 45% black.
  final Color overlayColor;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRect(frameRect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, Paint()..color = overlayColor);
  }

  @override
  bool shouldRepaint(ScannerOverlayPainter oldDelegate) =>
      oldDelegate.frameRect != frameRect ||
      oldDelegate.overlayColor != overlayColor;
}

/// A widget that dims everything outside the scan frame.
///
/// Wrap this around your camera preview inside a [Stack] to apply the overlay:
///
/// ```dart
/// Stack(
///   fit: StackFit.expand,
///   children: [
///     CameraPreview(controller),
///     ScannerOverlay(frameRect: myFrameRect),
///   ],
/// )
/// ```
class ScannerOverlay extends StatelessWidget {
  const ScannerOverlay({
    required this.frameRect,
    this.overlayColor = const Color(0x73000000),
    super.key,
  });

  final Rect frameRect;
  final Color overlayColor;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: ScannerOverlayPainter(
        frameRect: frameRect,
        overlayColor: overlayColor,
      ),
    );
  }
}
