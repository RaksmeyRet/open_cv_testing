import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

class FourCornerCropScreen extends StatefulWidget {
  const FourCornerCropScreen({required this.source, super.key});

  final File source;

  @override
  State<FourCornerCropScreen> createState() => _FourCornerCropScreenState();
}

class _FourCornerCropScreenState extends State<FourCornerCropScreen> {
  img.Image? _decodedImage;
  List<Offset>? _corners;
  int? _activeCorner;
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
        _decodedImage = image;
        _corners = [
          const Offset(.08, .12),
          const Offset(.92, .12),
          const Offset(.92, .88),
          const Offset(.08, .88),
        ];
      });
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not load image: $error');
    }
  }

  Future<void> _apply() async {
    final image = _decodedImage;
    final corners = _corners;
    if (image == null || corners == null) return;

    final topWidth = (corners[1].dx - corners[0].dx).abs() * image.width;
    final bottomWidth = (corners[2].dx - corners[3].dx).abs() * image.width;
    final leftHeight = (corners[3].dy - corners[0].dy).abs() * image.height;
    final rightHeight = (corners[2].dy - corners[1].dy).abs() * image.height;
    final outputWidth = math.max(1, math.max(topWidth, bottomWidth).round());
    final outputHeight = math.max(1, math.max(leftHeight, rightHeight).round());

    final result = img.copyRectify(
      image,
      topLeft: img.Point(corners[0].dx * image.width, corners[0].dy * image.height),
      topRight: img.Point(corners[1].dx * image.width, corners[1].dy * image.height),
      bottomLeft: img.Point(corners[3].dx * image.width, corners[3].dy * image.height),
      bottomRight: img.Point(corners[2].dx * image.width, corners[2].dy * image.height),
      interpolation: img.Interpolation.linear,
      toImage: img.Image(width: outputWidth, height: outputHeight, numChannels: 3),
    );
    final encoded = Uint8List.fromList(img.encodeJpg(result, quality: 92));
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/manual_crop_${DateTime.now().millisecondsSinceEpoch}.jpg');
    await file.writeAsBytes(encoded, flush: true);
    if (mounted) Navigator.of(context).pop(file);
  }

  void _updateCorner(Offset localPosition, Size size) {
    final corners = _corners;
    if (corners == null || _activeCorner == null) return;
    final next = Offset(
      (localPosition.dx / size.width).clamp(.02, .98),
      (localPosition.dy / size.height).clamp(.02, .98),
    );
    final index = _activeCorner!;
    final bounded = Offset(
      next.dx.clamp(.02, .98),
      next.dy.clamp(.02, .98),
    );
    setState(() => corners[index] = bounded);
  }

  @override
  Widget build(BuildContext context) {
    final image = _decodedImage;
    final corners = _corners;
    return Scaffold(
      backgroundColor: const Color(0xff101522),
      appBar: AppBar(
        title: const Text('Adjust ID card corners'),
        backgroundColor: const Color(0xff101522),
        foregroundColor: Colors.white,
        actions: [
          TextButton(onPressed: corners == null ? null : _apply, child: const Text('APPLY')),
        ],
      ),
      body: _error != null
          ? Center(child: Text(_error!, style: const TextStyle(color: Colors.white)))
          : image == null || corners == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 14, 20, 12),
                  child: Text('Drag each corner onto the edge of the card', style: TextStyle(color: Colors.white70)),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final size = Size(constraints.maxWidth, constraints.maxHeight);
                      return GestureDetector(
                        onPanStart: (details) {
                          var nearest = 0;
                          var distance = double.infinity;
                          for (var index = 0; index < corners.length; index++) {
                            final point = Offset(corners[index].dx * size.width, corners[index].dy * size.height);
                            final currentDistance = (point - details.localPosition).distance;
                            if (currentDistance < distance) {
                              nearest = index;
                              distance = currentDistance;
                            }
                          }
                          if (distance < 70) setState(() => _activeCorner = nearest);
                        },
                        onPanUpdate: (details) => _updateCorner(details.localPosition, size),
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
                    child: OutlinedButton.icon(
                      onPressed: () => setState(() => _corners = [const Offset(.08, .12), const Offset(.92, .12), const Offset(.92, .88), const Offset(.08, .88)]),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reset corners'),
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
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
    final points = corners.map((corner) => Offset(corner.dx * size.width, corner.dy * size.height)).toList();
    final path = Path()..moveTo(points[0].dx, points[0].dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = Colors.black54..style = PaintingStyle.fill);
    canvas.drawPath(path, Paint()..color = const Color(0xff54d6c7)..strokeWidth = 3..style = PaintingStyle.stroke);
    for (final point in points) {
      canvas.drawCircle(point, 18, Paint()..color = Colors.white);
      canvas.drawCircle(point, 13, Paint()..color = const Color(0xff243b7a));
    }
  }

  @override
  bool shouldRepaint(_CropPainter oldDelegate) => true;
}