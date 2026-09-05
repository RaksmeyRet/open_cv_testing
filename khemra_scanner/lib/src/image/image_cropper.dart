import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image/image.dart' as img;
import 'package:native_opencv_kit/native_opencv.dart';
import 'package:path_provider/path_provider.dart';

// ---------------------------------------------------------------------------
// Background isolate helpers
// ---------------------------------------------------------------------------

/// Runs native corner detection off the UI isolate.
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

/// Performs the actual perspective-crop off the UI isolate.
Future<Uint8List> _cropImageInBackground(
  Map<String, dynamic> input,
) async {
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

// ---------------------------------------------------------------------------
// GetX controller
// ---------------------------------------------------------------------------

/// Controller for the four-corner crop screen.
class ImageCropperController extends GetxController {
  ImageCropperController(this.source);

  final File source;

  final Rxn<img.Image> decodedImage = Rxn<img.Image>();
  final Rxn<Uint8List> sourceBytes = Rxn<Uint8List>();
  final corners = <Offset>[].obs;
  final activeCorner = (-1).obs;
  final isApplying = false.obs;
  final isDetecting = false.obs;
  final error = RxnString();

  static const double _idCardAspectRatio = 1.586;

  @override
  void onInit() {
    super.onInit();
    _loadImage();
  }

  Future<void> _loadImage() async {
    try {
      final bytes = await source.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) throw Exception('Unsupported image');
      final image = img.bakeOrientation(decoded);
      sourceBytes.value = bytes;
      decodedImage.value = image;
      corners.assignAll(_fallbackCorners(image));
      unawaited(_autoDetectCorners(image));
    } catch (err) {
      error.value = 'Could not load image: $err';
    }
  }

  Future<void> _autoDetectCorners(img.Image image) async {
    isDetecting.value = true;
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
      if (values == null) return;
      corners.assignAll([
        Offset(values[0], values[1]),
        Offset(values[2], values[3]),
        Offset(values[4], values[5]),
        Offset(values[6], values[7]),
      ]);
    } catch (err) {
      debugPrint('Auto-detect corners failed: $err');
    } finally {
      isDetecting.value = false;
    }
  }

  List<Offset> _fallbackCorners(img.Image image) {
    const horizontalPadding = .08;
    final width = 1 - (horizontalPadding * 2);
    final height =
        width * image.width / image.height / _idCardAspectRatio;
    final top = ((1 - height) / 2).clamp(.02, .98 - height);
    return [
      Offset(horizontalPadding, top),
      Offset(1 - horizontalPadding, top),
      Offset(1 - horizontalPadding, top + height),
      Offset(horizontalPadding, top + height),
    ];
  }

  /// Applies the crop and pops the route with the resulting [File].
  Future<void> apply() async {
    final image = decodedImage.value;
    if (image == null || corners.isEmpty) return;

    activeCorner.value = -1;
    isApplying.value = true;
    try {
      final bytes = sourceBytes.value ?? await source.readAsBytes();
      final encoded = await compute(_cropImageInBackground, {
        'bytes': bytes,
        'corners':
            corners.expand((c) => <double>[c.dx, c.dy]).toList(),
      });
      final directory = await getTemporaryDirectory();
      final file = File(
        '${directory.path}/khemra_crop_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await file.writeAsBytes(encoded, flush: true);
      Get.back(result: file);
    } catch (err) {
      error.value = 'Could not crop image: $err';
    } finally {
      isApplying.value = false;
    }
  }

  /// Updates the position of the active corner during a drag gesture.
  void updateCorner(Offset localPosition, Size size) {
    if (activeCorner.value < 0 || corners.isEmpty) return;
    final next = Offset(
      (localPosition.dx / size.width).clamp(.02, .98),
      (localPosition.dy / size.height).clamp(.02, .98),
    );
    final index = activeCorner.value;
    corners[index] = Offset(next.dx.clamp(.02, .98), next.dy.clamp(.02, .98));
  }
}

// ---------------------------------------------------------------------------
// Screen widget
// ---------------------------------------------------------------------------

/// Fullscreen screen that allows the user to adjust four crop corners on an
/// image, then crops the image to a perspective-corrected rectangle.
class KhemraImageCropperScreen extends StatelessWidget {
  const KhemraImageCropperScreen({required this.source, super.key});

  final File source;

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(ImageCropperController(source));

    return Obx(() {
      final image = controller.decodedImage.value;
      final corners = controller.corners;

      if (controller.error.value != null) {
        return Scaffold(
          body: Center(
            child: Text(
              controller.error.value!,
              style: const TextStyle(color: Colors.black87),
            ),
          ),
        );
      }

      if (image == null || controller.isDetecting.value || corners.isEmpty) {
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      }

      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text(
            'តម្រឹមរូបថតអត្តសញ្ញាណប័ណ្ណ',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF092469),
          centerTitle: true,
        ),
        body: Column(
          children: [
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
                          for (var i = 0; i < corners.length; i++) {
                            final point = Offset(
                              corners[i].dx * previewSize.width,
                              corners[i].dy * previewSize.height,
                            );
                            final d =
                                (point - details.localPosition).distance;
                            if (d < distance) {
                              nearest = i;
                              distance = d;
                            }
                          }
                          if (distance < 70) {
                            controller.activeCorner.value = nearest;
                          }
                        },
                        onPanUpdate: (details) => controller.updateCorner(
                          details.localPosition,
                          previewSize,
                        ),
                        onPanEnd: (_) => controller.activeCorner.value = -1,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.file(source, fit: BoxFit.fill),
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
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Get.back(),
                        icon: const Icon(Icons.camera_alt_outlined),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF092469),
                          side: const BorderSide(color: Color(0xFFEAEAEA)),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        label: const Text('ថតរូបឡើងវិញ'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed:
                            controller.isApplying.value
                                ? null
                                : controller.apply,
                        icon: controller.isApplying.value
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.arrow_forward_rounded),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF092469),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        label: Text(
                          controller.isApplying.value
                              ? 'កំពុងច្រិប...'
                              : 'បន្ទាប់',
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
    });
  }
}

// ---------------------------------------------------------------------------
// Painter
// ---------------------------------------------------------------------------

class _CropPainter extends CustomPainter {
  _CropPainter(this.corners);

  final List<Offset> corners;

  @override
  void paint(Canvas canvas, Size size) {
    final points = corners
        .map((c) => Offset(c.dx * size.width, c.dy * size.height))
        .toList();
    final path = Path()..moveTo(points[0].dx, points[0].dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFFCF951B)
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke,
    );
    for (final point in points) {
      canvas.drawCircle(point, 11, Paint()..color = Colors.white);
      canvas.drawCircle(point, 7, Paint()..color = const Color(0xFF092469));
    }
  }

  @override
  bool shouldRepaint(_CropPainter oldDelegate) => true;
}
