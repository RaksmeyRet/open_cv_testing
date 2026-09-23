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

// Keep a single, consistent working orientation: landscape for card detection.
// This matches the user flow: rotate to standing first, then detect and let
// the user fine-tune the corners.

img.Image _prepareStandingImage(img.Image image) {
  final oriented = img.bakeOrientation(image);
  if (oriented.width < oriented.height) {
    final rotated = img.copyRotate(oriented, angle: -90);
    if (rotated.width > 0 && rotated.height > 0) {
      return rotated;
    }
  }
  return oriented;
}

img.Image _normalizeWorkingImage(img.Image image) {
  return _prepareStandingImage(image);
}

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
Future<Uint8List> _cropImageInBackground(Map<String, dynamic> input) async {
  final sourceBytes = input['bytes'] as Uint8List;
  final values = input['corners'] as List<double>;
  final source = img.decodeImage(sourceBytes);
  if (source == null) throw Exception('Unsupported image');

  // Normalize the original file the same way as the detection preview.
  final image = _normalizeWorkingImage(source);
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

List<Offset> normalizeCardCorners(List<Offset> corners) {
  if (corners.length != 4) return List<Offset>.from(corners);

  final centerX = corners.map((c) => c.dx).reduce((a, b) => a + b) / 4;
  final centerY = corners.map((c) => c.dy).reduce((a, b) => a + b) / 4;

  final orderedByAngle = List<Offset>.from(corners)..sort((a, b) {
    final angleA = math.atan2(a.dy - centerY, a.dx - centerX);
    final angleB = math.atan2(b.dy - centerY, b.dx - centerX);
    return angleA.compareTo(angleB);
  });

  final topLeft = orderedByAngle.reduce((best, current) {
    final bestScore = best.dx + best.dy;
    final currentScore = current.dx + current.dy;
    return currentScore < bestScore ? current : best;
  });

  final startIndex = orderedByAngle.indexOf(topLeft);
  final rotated = <Offset>[];
  for (var i = 0; i < 4; i++) {
    rotated.add(orderedByAngle[(startIndex + i) % 4]);
  }

  return rotated;
}

/// Controller for the four-corner crop screen.
class ImageCropperController extends GetxController {
  ImageCropperController(this.source, {required this.onComplete});

  static List<Offset> convertDetectedCornersToSource({
    required List<double> normalizedCorners,
    required int detectionWidth,
    required int detectionHeight,
    required int candidateWidth,
    required int candidateHeight,
    required int offsetX,
    required int offsetY,
    required int sourceWidth,
    required int sourceHeight,
  }) {
    if (normalizedCorners.length != 8) {
      return const <Offset>[];
    }

    if (detectionWidth <= 0 || detectionHeight <= 0) {
      return const <Offset>[];
    }

    final scaleX = candidateWidth / detectionWidth;
    final scaleY = candidateHeight / detectionHeight;

    final corners = <Offset>[];
    for (var i = 0; i < 4; i++) {
      final rawX = normalizedCorners[i * 2];
      final rawY = normalizedCorners[i * 2 + 1];
      final localX = rawX * detectionWidth;
      final localY = rawY * detectionHeight;
      final mappedX = offsetX + (localX * scaleX);
      final mappedY = offsetY + (localY * scaleY);
      corners.add(Offset(mappedX / sourceWidth, mappedY / sourceHeight));
    }
    return corners;
  }

  final File source;
  final ValueChanged<File> onComplete;

  final Rxn<img.Image> decodedImage = Rxn<img.Image>();
  final Rxn<Uint8List> sourceBytes = Rxn<Uint8List>();
  Uint8List? previewBytes;
  final corners = <Offset>[].obs;
  final activeCorner = (-1).obs;
  final isApplying = false.obs;
  final isDetecting = false.obs;
  final error = RxnString();
  bool _autoDetectStarted = false;

  static const double _idCardAspectRatio = 1.586;

  static List<Offset> _normalizeDetectedCorners(List<Offset> corners) {
    return normalizeCardCorners(corners);
  }

  static double _quadrilateralArea(List<Offset> corners) {
    var area = 0.0;
    for (var i = 0; i < corners.length; i++) {
      final next = corners[(i + 1) % corners.length];
      area += corners[i].dx * next.dy - next.dx * corners[i].dy;
    }
    return area.abs() / 2;
  }

  static bool _hasDistinctCorners(List<Offset> corners) {
    return corners.toSet().length == 4;
  }

  static bool _looksLikeCard(List<Offset> corners) {
    if (corners.length != 4 || !_hasDistinctCorners(corners)) return false;
    if (_quadrilateralArea(corners) < 0.08) return false;

    final topWidth = (corners[1].dx - corners[0].dx).abs();
    final bottomWidth = (corners[2].dx - corners[3].dx).abs();
    final leftHeight = (corners[3].dy - corners[0].dy).abs();
    final rightHeight = (corners[2].dy - corners[1].dy).abs();

    final width = math.max(topWidth, bottomWidth);
    final height = math.max(leftHeight, rightHeight);

    if (width <= 0.08 || height <= 0.06) return false;

    final ratio = width / height;
    final expectedRatio = 1.586;
    final ratioDelta = (ratio - expectedRatio).abs();
    return ratioDelta <= 0.6;
  }

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

      final image = _normalizeWorkingImage(decoded);
      decodedImage.value = image;
      final previewImage =
          image.width > 1600 ? img.copyResize(image, width: 1600) : image;
      previewBytes = Uint8List.fromList(
        img.encodeJpg(previewImage, quality: 85),
      );
      corners.clear();
      if (!_autoDetectStarted) {
        _autoDetectStarted = true;
        unawaited(_autoDetectCorners(image));
      }
    } catch (err) {
      error.value = 'Could not load image: $err';
    }
  }

  Future<void> _autoDetectCorners(img.Image image) async {
    if (_autoDetectStarted == false) {
      _autoDetectStarted = true;
    }
    isDetecting.value = true;
    try {
      final detectionImage =
          image.width > 1200 ? img.copyResize(image, width: 1200) : image;
      final candidates = <
        ({
          img.Image image,
          int offsetX,
          int offsetY,
          int sourceWidth,
          int sourceHeight,
        })
      >[
        (
          image: detectionImage,
          offsetX: 0,
          offsetY: 0,
          sourceWidth: image.width,
          sourceHeight: image.height,
        ),
      ];

      // Center crops make a far-away card larger relative to the detector's
      // working frame. The full-image attempt above preserves close cards.
      for (final marginFraction in [0.10, 0.20, 0.30]) {
        final marginX = (detectionImage.width * marginFraction).round();
        final marginY = (detectionImage.height * marginFraction).round();
        final cropWidth = detectionImage.width - marginX * 2;
        final cropHeight = detectionImage.height - marginY * 2;
        if (cropWidth < 32 || cropHeight < 32) continue;

        final cropped = img.copyCrop(
          detectionImage,
          x: marginX,
          y: marginY,
          width: cropWidth,
          height: cropHeight,
        );
        final resized =
            cropped.width > 1200
                ? img.copyResize(cropped, width: 1200)
                : cropped;
        candidates.add((
          image: resized,
          offsetX: marginX,
          offsetY: marginY,
          sourceWidth: image.width,
          sourceHeight: image.height,
        ));
      }

      for (final candidate in candidates) {
        final values = await _detectFromCandidate(candidate);
        if (values != null) {
          final normalized = _normalizeDetectedCorners(values);
          if (_looksLikeCard(normalized)) {
            corners.assignAll(normalized);
            return;
          }
        }
      }

      // Keep the crop usable when native detection cannot find a card.
      corners.assignAll(_fallbackCorners(image));
    } catch (err) {
      debugPrint('Auto-detect corners failed: $err');
      corners.assignAll(_fallbackCorners(image));
    } finally {
      isDetecting.value = false;
    }
  }

  List<Offset> _fallbackCorners(img.Image image) {
    const width = .46;
    final height = width * image.width / image.height / _idCardAspectRatio;
    final left = (1 - width) / 2;
    final top = ((1 - height) / 2).clamp(.02, .98 - height);
    return [
      Offset(left, top),
      Offset(left + width, top),
      Offset(left + width, top + height),
      Offset(left, top + height),
    ];
  }

  Future<List<Offset>?> _detectFromCandidate(
    ({
      img.Image image,
      int offsetX,
      int offsetY,
      int sourceWidth,
      int sourceHeight,
    })
    candidate,
  ) async {
    final detectionImage = candidate.image;

    final values = await compute(_detectCornersInBackground, {
      'rgba': detectionImage.getBytes(order: img.ChannelOrder.rgba),
      'width': detectionImage.width,
      'height': detectionImage.height,
      'originalWidth': detectionImage.width,
      'originalHeight': detectionImage.height,
    });

    if (values == null) return null;

    return convertDetectedCornersToSource(
      normalizedCorners: values,
      detectionWidth: detectionImage.width,
      detectionHeight: detectionImage.height,
      candidateWidth: candidate.image.width,
      candidateHeight: candidate.image.height,
      offsetX: candidate.offsetX,
      offsetY: candidate.offsetY,
      sourceWidth: candidate.sourceWidth,
      sourceHeight: candidate.sourceHeight,
    );
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
        'corners': corners.expand((c) => <double>[c.dx, c.dy]).toList(),
      });
      final directory = await getTemporaryDirectory();
      final file = File(
        '${directory.path}/khemra_crop_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await file.writeAsBytes(encoded, flush: true);
      onComplete(file);
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
    final navigator = Navigator.of(context);
    final controller = Get.put(
      ImageCropperController(
        source,
        onComplete: (file) {
          if (navigator.mounted) navigator.pop(file);
        },
      ),
      tag: source.path,
    );

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

      if (image == null || controller.previewBytes == null) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
                          if (corners.isEmpty) return;
                          var nearest = 0;
                          var distance = double.infinity;
                          for (var i = 0; i < corners.length; i++) {
                            final point = Offset(
                              corners[i].dx * previewSize.width,
                              corners[i].dy * previewSize.height,
                            );
                            final d = (point - details.localPosition).distance;
                            if (d < distance) {
                              nearest = i;
                              distance = d;
                            }
                          }
                          if (distance < 70) {
                            controller.activeCorner.value = nearest;
                          }
                        },
                        onPanUpdate:
                            (details) => controller.updateCorner(
                              details.localPosition,
                              previewSize,
                            ),
                        onPanEnd: (_) => controller.activeCorner.value = -1,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.memory(
                              controller.previewBytes!,
                              fit: BoxFit.fill,
                              gaplessPlayback: true,
                            ),
                            if (corners.isNotEmpty)
                              CustomPaint(painter: _CropPainter(corners)),
                            if (controller.isDetecting.value)
                              Positioned.fill(
                                child: Container(
                                  color: Colors.black54,
                                  child: Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 3,
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          'កំពុងស្វែងរក...',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
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
                        onPressed: () => Navigator.of(context).pop(),
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
                            controller.isApplying.value ||
                                    controller.isDetecting.value ||
                                    corners.isEmpty
                                ? null
                                : controller.apply,
                        icon:
                            controller.isApplying.value ||
                                    controller.isDetecting.value
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
                              : controller.isDetecting.value
                              ? 'កំពុងស្វែងរក...'
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
    final points =
        corners
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
