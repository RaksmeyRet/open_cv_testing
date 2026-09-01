import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:native_opencv_kit/native_opencv.dart';
import 'package:path_provider/path_provider.dart';

const List<Offset> _defaultCorners = [
  Offset(.08, .12),
  Offset(.92, .12),
  Offset(.92, .88),
  Offset(.08, .88),
];

/// Runs native corner detection on a decoded image. Must run off the UI
/// isolate since native_opencv_kit's FFI call does CPU-heavy OpenCV work.
/// Only primitive/TypedData values are passed since `compute` serializes
/// the input across an isolate boundary.
List<double>? _detectCornersInBackground(Map<String, dynamic> input) {
  final rgba = input['rgba'] as Uint8List;
  final width = input['width'] as int;
  final height = input['height'] as int;
  final corners = NativeOpencv.detectIdCardCorners(rgba, width, height);
  if (corners == null) return null;
  return corners
      .expand((corner) => <double>[corner.dx, corner.dy])
      .toList();
}

Future<Uint8List> _cropImageInBackground(Map<String, dynamic> input) async {
  final sourceBytes = input['bytes'] as Uint8List;
  final values = input['corners'] as List<double>;
  final source = img.decodeImage(sourceBytes);
  if (source == null) throw Exception('Unsupported image');

  final image = img.bakeOrientation(source);
  final corners = [
    Offset(values[0], values[1]),
    Offset(values[2], values[3]),
    Offset(values[4], values[5]),
    Offset(values[6], values[7]),
  ];
  final topWidth = (corners[1].dx - corners[0].dx).abs() * image.width;
  final bottomWidth = (corners[2].dx - corners[3].dx).abs() * image.width;
  final leftHeight = (corners[3].dy - corners[0].dy).abs() * image.height;
  final rightHeight = (corners[2].dy - corners[1].dy).abs() * image.height;
  final cropWidth = math.max(1, math.max(topWidth, bottomWidth));
  final cropHeight = math.max(1, math.max(leftHeight, rightHeight));
  final outputScale = math.min(
    1.0,
    math.min(1600 / cropWidth, 1000 / cropHeight),
  );
  final outputWidth = math.max(1, (cropWidth * outputScale).round());
  final outputHeight = math.max(1, (cropHeight * outputScale).round());

  final result = img.copyRectify(
    image,
    topLeft: img.Point(
      corners[0].dx * image.width,
      corners[0].dy * image.height,
    ),
    topRight: img.Point(
      corners[1].dx * image.width,
      corners[1].dy * image.height,
    ),
    bottomLeft: img.Point(
      corners[3].dx * image.width,
      corners[3].dy * image.height,
    ),
    bottomRight: img.Point(
      corners[2].dx * image.width,
      corners[2].dy * image.height,
    ),
    interpolation: img.Interpolation.linear,
    toImage: img.Image(
      width: outputWidth,
      height: outputHeight,
      numChannels: 3,
    ),
  );
  return Uint8List.fromList(img.encodeJpg(result, quality: 92));
}

class FourCornerCropScreen extends StatefulWidget {
  const FourCornerCropScreen({required this.source, super.key});

  final File source;

  @override
  State<FourCornerCropScreen> createState() => _FourCornerCropScreenState();
}

class _FourCornerCropScreenState extends State<FourCornerCropScreen> {
  img.Image? _decodedImage;
  Uint8List? _sourceBytes;
  List<Offset>? _corners;
  int? _activeCorner;
  bool _isApplying = false;
  bool _isDetecting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    try {
      final bytes = await widget.source.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (!mounted || decoded == null) throw Exception('Unsupported image');
      final image = img.bakeOrientation(decoded);
      setState(() {
        _sourceBytes = bytes;
        _decodedImage = image;
        _corners = List.of(_defaultCorners);
      });
      unawaited(_autoDetectCorners(image));
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not load image: $error');
    }
  }

  Future<void> _autoDetectCorners(img.Image image) async {
    setState(() => _isDetecting = true);
    try {
      final values = await compute(_detectCornersInBackground, {
        'rgba': image.getBytes(order: img.ChannelOrder.rgba),
        'width': image.width,
        'height': image.height,
      });
      if (!mounted || values == null) return;
      setState(() {
        _corners = [
          Offset(values[0] / image.width, values[1] / image.height),
          Offset(values[2] / image.width, values[3] / image.height),
          Offset(values[4] / image.width, values[5] / image.height),
          Offset(values[6] / image.width, values[7] / image.height),
        ];
      });
    } catch (error) {
      debugPrint('Auto-detect corners failed: $error');
    } finally {
      if (mounted) setState(() => _isDetecting = false);
    }
  }

  Future<void> _apply() async {
    final image = _decodedImage;
    final corners = _corners;
    if (image == null || corners == null) return;

    setState(() {
      _activeCorner = null;
      _isApplying = true;
    });
    try {
      final sourceBytes = _sourceBytes ?? await widget.source.readAsBytes();
      final encoded = await compute(_cropImageInBackground, {
        'bytes': sourceBytes,
        'corners':
            corners.expand((corner) => <double>[corner.dx, corner.dy]).toList(),
      });
      final directory = await getTemporaryDirectory();
      final file = File(
        '${directory.path}/manual_crop_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await file.writeAsBytes(encoded, flush: true);
      if (!mounted) return;
      final proceed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => CroppedImagePreviewScreen(image: file),
        ),
      );
      if (mounted && proceed == true) Navigator.of(context).pop(file);
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not crop image: $error');
    } finally {
      if (mounted) setState(() => _isApplying = false);
    }
  }

  void _updateCorner(Offset localPosition, Size size) {
    final corners = _corners;
    if (corners == null || _activeCorner == null) return;
    final next = Offset(
      (localPosition.dx / size.width).clamp(.02, .98),
      (localPosition.dy / size.height).clamp(.02, .98),
    );
    final index = _activeCorner!;
    final bounded = Offset(next.dx.clamp(.02, .98), next.dy.clamp(.02, .98));
    setState(() => corners[index] = bounded);
  }

  @override
  Widget build(BuildContext context) {
    final image = _decodedImage;
    final corners = _corners;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Adjust ID card corners'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        actions: [
          TextButton(
            onPressed: corners == null || _isApplying ? null : _apply,
            child: Text(_isApplying ? 'CROPPING...' : 'APPLY'),
          ),
        ],
      ),
      body:
          _error != null
              ? Center(
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.black87),
                ),
              )
              : image == null || corners == null
              ? const Center(child: CircularProgressIndicator())
              : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
                    child: Text(
                      _isDetecting
                          ? 'Detecting card edges...'
                          : 'Drag each corner onto the edge of the card',
                      style: const TextStyle(color: Colors.black54),
                    ),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final size = Size(
                          constraints.maxWidth,
                          constraints.maxHeight,
                        );
                        return GestureDetector(
                          onPanStart: (details) {
                            var nearest = 0;
                            var distance = double.infinity;
                            for (
                              var index = 0;
                              index < corners.length;
                              index++
                            ) {
                              final point = Offset(
                                corners[index].dx * size.width,
                                corners[index].dy * size.height,
                              );
                              final currentDistance =
                                  (point - details.localPosition).distance;
                              if (currentDistance < distance) {
                                nearest = index;
                                distance = currentDistance;
                              }
                            }
                            if (distance < 70) {
                              setState(() => _activeCorner = nearest);
                            }
                          },
                          onPanUpdate:
                              (details) =>
                                  _updateCorner(details.localPosition, size),
                          onPanEnd: (_) => setState(() => _activeCorner = null),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.file(widget.source, fit: BoxFit.fill),
                              CustomPaint(painter: _CropPainter(corners)),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed:
                                  () => setState(
                                    () => _corners = List.of(_defaultCorners),
                                  ),
                              icon: const Icon(Icons.refresh),
                              label: const Text('Reset corners'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.black87,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed:
                                  _isDetecting
                                      ? null
                                      : () => _autoDetectCorners(image),
                              icon: const Icon(Icons.center_focus_strong),
                              label: const Text('Auto detect'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.black87,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
    );
  }
}

class CroppedImagePreviewScreen extends StatelessWidget {
  const CroppedImagePreviewScreen({required this.image, super.key});

  final File image;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Cropped ID card'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Center(child: Image.file(image, fit: BoxFit.contain)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(true),
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('NEXT'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CropPainter extends CustomPainter {
  _CropPainter(this.corners);

  final List<Offset> corners;

  @override
  void paint(Canvas canvas, Size size) {
    final points =
        corners
            .map(
              (corner) =>
                  Offset(corner.dx * size.width, corner.dy * size.height),
            )
            .toList();
    final path = Path()..moveTo(points[0].dx, points[0].dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xff54d6c7)
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke,
    );
    for (final point in points) {
      canvas.drawCircle(point, 11, Paint()..color = Colors.white);
      canvas.drawCircle(point, 7, Paint()..color = const Color(0xff243b7a));
    }
  }

  @override
  bool shouldRepaint(_CropPainter oldDelegate) => true;
}
