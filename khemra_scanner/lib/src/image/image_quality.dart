import 'package:native_opencv_kit/native_opencv.dart';

/// Checks whether an image is blurred using native OpenCV.
abstract final class ImageQuality {
  /// Returns `true` if the RGBA [bytes] at [width] × [height] resolution are
  /// considered blurry by the native OpenCV blur detector.
  static bool isBlurred(
    List<int> bytes,
    int width,
    int height,
  ) {
    return NativeOpencv.isImageBlurred(bytes as dynamic, width, height);
  }
}
