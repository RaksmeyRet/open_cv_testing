import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:native_opencv_kit/native_opencv.dart';

/// Detects the corners of a Cambodian ID card in an RGBA image using
/// native OpenCV.
abstract final class IdCardDetector {
  /// The standard output width (pixels) for a cropped ID card image.
  static int get outputWidth => NativeOpencv.idCardOutputWidth;

  /// The standard output height (pixels) for a cropped ID card image.
  static int get outputHeight => NativeOpencv.idCardOutputHeight;

  /// Detects the four corners of an ID card in the [rgba] buffer at
  /// [width] × [height] resolution.
  ///
  /// Returns a list of four [Offset] values (top-left, top-right,
  /// bottom-right, bottom-left) in pixel coordinates, or `null` if
  /// no card was detected.
  static List<Offset>? detectCorners(
    Uint8List rgba,
    int width,
    int height,
  ) {
    return NativeOpencv.detectIdCardCorners(rgba, width, height);
  }

  /// Perspective-crops and deskews the ID card region in [rgba] to a
  /// standard resolution defined by [outputWidth] × [outputHeight].
  ///
  /// Returns the cropped RGBA bytes, or `null` if no card was detected.
  static Uint8List? cropIdCard(
    Uint8List rgba,
    int width,
    int height,
  ) {
    return NativeOpencv.cropIdCard(rgba, width, height);
  }
}
