import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:native_opencv_kit/native_opencv.dart';
import 'package:path_provider/path_provider.dart';

import 'core/colors/app_colors.dart';

/// Runs native corner detection on a decoded image. Must run off the UI
/// isolate since native_opencv_kit's FFI call does CPU-heavy OpenCV work.
/// Only primitive/TypedData values are passed since `compute` serializes
/// the input across an isolate boundary.
List<double>? _detectCornersInBackground(Map<String, dynamic> input) {
  final rgba = input['rgba'] as Uint8List;
  final width = input['width'] as int;
  final height = input['height'] as int;
  final originalWidth = input['originalWidth'] as int;
  final originalHeight = input['originalHeight'] as int;
  final corners = NativeOpencv.detectIdCardCorners(rgba, width, height);
  if (corners == null) return null;
  return corners
      .expand(
        (corner) => <double>[
          corner.dx / originalWidth,
          corner.dy / originalHeight,
        ],
      )
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

  static const _idCardAspectRatio = 1.586;

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
        _corners = _fallbackCorners(image);
      });
      unawaited(_autoDetectCorners(image));
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not load image: $error');
    }
  }

  Future<void> _autoDetectCorners(img.Image image) async {
    try {
      const detectionWidth = 960;
      final detectionImage =
          image.width > detectionWidth
              ? img.copyResize(image, width: detectionWidth)
              : image;
      final values = await compute(_detectCornersInBackground, {
        'rgba': detectionImage.getBytes(order: img.ChannelOrder.rgba),
        'width': detectionImage.width,
        'height': detectionImage.height,
        'originalWidth': detectionImage.width,
        'originalHeight': detectionImage.height,
      });
      if (!mounted) return;
      if (values == null) return;
      setState(
        () =>
            _corners = [
              Offset(values[0], values[1]),
              Offset(values[2], values[3]),
              Offset(values[4], values[5]),
              Offset(values[6], values[7]),
            ],
      );
    } catch (error) {
      debugPrint('Auto-detect corners failed: $error');
    } finally {
      if (mounted) setState(() => _isDetecting = false);
    }
  }

  List<Offset> _fallbackCorners(img.Image image) {
    const horizontalPadding = .08;
    final width = 1 - (horizontalPadding * 2);
    final height = width * image.width / image.height / _idCardAspectRatio;
    final top = ((1 - height) / 2).clamp(.02, .98 - height);
    return [
      Offset(horizontalPadding, top),
      Offset(1 - horizontalPadding, top),
      Offset(1 - horizontalPadding, top + height),
      Offset(horizontalPadding, top + height),
    ];
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
      Navigator.of(context).pop(file);
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
        title: const Text(
          'តម្រឹមរូបថតអត្តសញ្ញាណប័ណ្ណ',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        centerTitle: true,
      ),
      body:
          _error != null
              ? Center(
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.black87),
                ),
              )
              : image == null || _isDetecting || corners == null
              ? const Center(child: CircularProgressIndicator())
              : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
                    child: Text(
                      _isDetecting
                          ? 'កំពុងស្វែងរកគែមកាត...'
                          : 'ទាញជ្រុងនីមួយៗឲ្យចំគែមកាត',
                      style: const TextStyle(color: Colors.black54),
                    ),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final scale = math.min(
                          constraints.maxWidth / image.width,
                          constraints.maxHeight / image.height,
                        );
                        final previewSize = Size(
                          image.width * scale,
                          image.height * scale,
                        );
                        return Center(
                          child: SizedBox(
                            width: previewSize.width,
                            height: previewSize.height,
                            child: GestureDetector(
                              onPanStart: (details) {
                                var nearest = 0;
                                var distance = double.infinity;
                                for (
                                  var index = 0;
                                  index < corners.length;
                                  index++
                                ) {
                                  final point = Offset(
                                    corners[index].dx * previewSize.width,
                                    corners[index].dy * previewSize.height,
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
                                  (details) => _updateCorner(
                                    details.localPosition,
                                    previewSize,
                                  ),
                              onPanEnd:
                                  (_) => setState(() => _activeCorner = null),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.file(widget.source, fit: BoxFit.fill),
                                  CustomPaint(painter: _CropPainter(corners)),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Column(
                        children: [
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed:
                                  () => setState(
                                    () => _corners = _fallbackCorners(image),
                                  ),
                              icon: const Icon(Icons.refresh, size: 18),
                              label: const Text('កំណត់ជ្រុងឡើងវិញ'),
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.textSecondary,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.textPrimary,
                                    side: const BorderSide(
                                      color: AppColors.border,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: const Text('ថតរូបឡើងវិញ'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FilledButton(
                                  onPressed: _isApplying ? null : _apply,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.primaryDark,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: Text(
                                    _isApplying ? 'កំពុងច្រិប...' : 'បន្ទាប់',
                                  ),
                                ),
                              ),
                            ],
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
