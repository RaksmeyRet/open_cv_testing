import 'package:flutter/material.dart';

/// A single L-shaped corner indicator painted on the camera preview frame.
///
/// Use eight of these to form the four corners of the scan-guide rectangle:
/// ```dart
/// Stack(children: const [
///   ScannerFrameCorner(top: 0, left: 0, horizontal: true),
///   ScannerFrameCorner(top: 0, left: 0, horizontal: false),
///   ScannerFrameCorner(top: 0, right: 0, horizontal: true),
///   ScannerFrameCorner(top: 0, right: 0, horizontal: false),
///   ScannerFrameCorner(bottom: 0, left: 0, horizontal: true),
///   ScannerFrameCorner(bottom: 0, left: 0, horizontal: false),
///   ScannerFrameCorner(bottom: 0, right: 0, horizontal: true),
///   ScannerFrameCorner(bottom: 0, right: 0, horizontal: false),
/// ])
/// ```
class ScannerFrameCorner extends StatelessWidget {
  const ScannerFrameCorner({
    super.key,
    this.top,
    this.right,
    this.bottom,
    this.left,
    required this.horizontal,
    this.color = Colors.white,
    this.thickness = 6,
    this.length = 64,
  });

  final double? top;
  final double? right;
  final double? bottom;
  final double? left;

  /// Whether this bar runs horizontally (true) or vertically (false).
  final bool horizontal;

  /// Colour of the corner bar. Defaults to white.
  final Color color;

  /// Thickness of the bar in logical pixels. Defaults to 6.
  final double thickness;

  /// Length of the bar in logical pixels. Defaults to 64.
  final double length;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: top,
      right: right,
      bottom: bottom,
      left: left,
      child: Container(
        width: horizontal ? length : thickness,
        height: horizontal ? thickness : length,
        color: color,
      ),
    );
  }
}

/// Convenience widget that builds all eight [ScannerFrameCorner] pieces
/// for a complete scan-guide frame.
class ScannerFrame extends StatelessWidget {
  const ScannerFrame({
    super.key,
    this.color = Colors.white,
    this.thickness = 6,
    this.length = 64,
  });

  final Color color;
  final double thickness;
  final double length;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ScannerFrameCorner(
          top: 0,
          left: 0,
          horizontal: true,
          color: color,
          thickness: thickness,
          length: length,
        ),
        ScannerFrameCorner(
          top: 0,
          left: 0,
          horizontal: false,
          color: color,
          thickness: thickness,
          length: length,
        ),
        ScannerFrameCorner(
          top: 0,
          right: 0,
          horizontal: true,
          color: color,
          thickness: thickness,
          length: length,
        ),
        ScannerFrameCorner(
          top: 0,
          right: 0,
          horizontal: false,
          color: color,
          thickness: thickness,
          length: length,
        ),
        ScannerFrameCorner(
          bottom: 0,
          left: 0,
          horizontal: true,
          color: color,
          thickness: thickness,
          length: length,
        ),
        ScannerFrameCorner(
          bottom: 0,
          left: 0,
          horizontal: false,
          color: color,
          thickness: thickness,
          length: length,
        ),
        ScannerFrameCorner(
          bottom: 0,
          right: 0,
          horizontal: true,
          color: color,
          thickness: thickness,
          length: length,
        ),
        ScannerFrameCorner(
          bottom: 0,
          right: 0,
          horizontal: false,
          color: color,
          thickness: thickness,
          length: length,
        ),
      ],
    );
  }
}
