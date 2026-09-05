import 'dart:typed_data';
import 'dart:io';

import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:camera/camera.dart' show CameraImage, CameraLensDirection;

/// Handles pixel-format conversion and rotation for raw camera frames.
abstract final class ImageProcessor {
  static const Map<DeviceOrientation, int> _deviceOrientationDegrees = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  /// Converts a [CameraImage] to RGBA [Uint8List].
  ///
  /// Supports single-plane BGRA8888 (iOS) and multi-plane YUV420 (Android).
  static Uint8List? cameraImageToRgba(CameraImage image) {
    try {
      if (image.planes.length == 1) {
        return _bgra8888ToRgba(image);
      }
      return _yuv420ToRgba(image);
    } catch (e) {
      return null;
    }
  }

  /// Rotates [rgba] so the image appears upright on both iOS and Android.
  static ({Uint8List rgba, int width, int height}) applyRotation(
    Uint8List rgba,
    int width,
    int height,
    int sensorOrientation,
    DeviceOrientation deviceOrientation,
    CameraLensDirection lensDirection,
  ) {
    final deviceDegrees = _deviceOrientationDegrees[deviceOrientation] ?? 0;
    final degrees = Platform.isIOS
        ? sensorOrientation
        : lensDirection == CameraLensDirection.front
        ? (sensorOrientation + deviceDegrees) % 360
        : (sensorOrientation - deviceDegrees + 360) % 360;

    final swapped = degrees == 90 || degrees == 270;
    return (
      rgba: _rotate(rgba, width, height, degrees),
      width: swapped ? height : width,
      height: swapped ? width : height,
    );
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  static Uint8List _bgra8888ToRgba(CameraImage image) {
    final bytes = image.planes.first.bytes;
    final rgba = Uint8List(bytes.length);
    for (int i = 0; i < bytes.length; i += 4) {
      rgba[i] = bytes[i + 2];
      rgba[i + 1] = bytes[i + 1];
      rgba[i + 2] = bytes[i];
      rgba[i + 3] = bytes[i + 3];
    }
    return rgba;
  }

  static Uint8List _yuv420ToRgba(CameraImage image) {
    final int width = image.width;
    final int height = image.height;

    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final int yRowStride = yPlane.bytesPerRow;
    final int uvRowStride = uPlane.bytesPerRow;
    final int uvPixelStride = uPlane.bytesPerPixel ?? 1;

    final Uint8List rgba = Uint8List(width * height * 4);

    for (int row = 0; row < height; row++) {
      final int yRowOffset = row * yRowStride;
      final int uvRowOffset = (row >> 1) * uvRowStride;

      for (int col = 0; col < width; col++) {
        final int yIndex = yRowOffset + col;
        final int uvIndex = uvRowOffset + (col >> 1) * uvPixelStride;

        final int yValue = yPlane.bytes[yIndex];
        final int uValue = uPlane.bytes[uvIndex];
        final int vValue = vPlane.bytes[uvIndex];

        final int c = yValue - 16;
        final int d = uValue - 128;
        final int e = vValue - 128;

        int r = (298 * c + 409 * e + 128) >> 8;
        int g = (298 * c - 100 * d - 208 * e + 128) >> 8;
        int b = (298 * c + 516 * d + 128) >> 8;

        final int pixelIndex = (row * width + col) * 4;
        rgba[pixelIndex] = r.clamp(0, 255);
        rgba[pixelIndex + 1] = g.clamp(0, 255);
        rgba[pixelIndex + 2] = b.clamp(0, 255);
        rgba[pixelIndex + 3] = 255;
      }
    }
    return rgba;
  }

  static Uint8List _rotate(
    Uint8List src,
    int width,
    int height,
    int degrees,
  ) {
    if (degrees == 0) return src;
    final outStride = degrees == 180 ? width : height;
    final out = Uint8List(width * height * 4);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final int newX;
        final int newY;
        switch (degrees) {
          case 90:
            newX = height - 1 - y;
            newY = x;
            break;
          case 270:
            newX = y;
            newY = width - 1 - x;
            break;
          default: // 180
            newX = width - 1 - x;
            newY = height - 1 - y;
        }

        final srcIndex = (y * width + x) * 4;
        final dstIndex = (newY * outStride + newX) * 4;
        out[dstIndex] = src[srcIndex];
        out[dstIndex + 1] = src[srcIndex + 1];
        out[dstIndex + 2] = src[srcIndex + 2];
        out[dstIndex + 3] = src[srcIndex + 3];
      }
    }
    return out;
  }
}
