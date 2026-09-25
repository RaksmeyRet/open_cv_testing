import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:native_opencv_kit/native_opencv.dart';

/// A higher-level document detector built on top of the native OpenCV layer.
///
/// This wraps [NativeOpencv] to provide a generic document detection
/// interface; for ID-card-specific logic prefer [IdCardDetector].
abstract final class DocumentDetector {
  /// Returns `true` when [rgba] at [width] × [height] is considered sharp
  /// enough for OCR processing.
  static bool isSharp(Uint8List rgba, int width, int height) {
    return !NativeOpencv.isImageBlurred(rgba, width, height);
  }

  /// Detects document corners in [rgba] at [width] × [height].
  ///
  /// Returns four corner [Offset] values or `null` if no document boundary
  /// was found.
  static List<Offset>? detectCorners(
    Uint8List rgba,
    int width,
    int height,
  ) {
    return NativeOpencv.detectIdCardCorners(rgba, width, height);
  }
}
