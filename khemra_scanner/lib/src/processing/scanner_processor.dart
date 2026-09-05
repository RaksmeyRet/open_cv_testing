import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:image/image.dart' as image_lib;

import '../result/scanner_result.dart';

typedef ScannerImageValidator = bool Function(
  Uint8List rgbaBytes,
  int width,
  int height,
);

/// Processes a captured image without exposing native implementation details.
class ScannerProcessor {
  final ScannerImageValidator? validator;

  const ScannerProcessor({this.validator});

  Future<KhemraScannerResult> process(XFile capture) async {
    try {
      final bytes = await capture.readAsBytes();
      image_lib.Image? decoded;
      try {
        decoded = image_lib.decodeImage(bytes);
      } on Object {
        return const KhemraScannerResult(isValid: false);
      }
      if (decoded == null) {
        return const KhemraScannerResult(isValid: false);
      }

      final rgba = Uint8List.fromList(
        decoded.getBytes(order: image_lib.ChannelOrder.rgba),
      );
      final isValid = validator?.call(rgba, decoded.width, decoded.height) ??
          true;
      if (!isValid) {
        return KhemraScannerResult(imagePath: capture.path, isValid: false);
      }

      return KhemraScannerResult(
        imagePath: capture.path,
        isValid: true,
      );
    } on Object catch (error) {
      throw KhemraScannerException(
        'The captured image could not be processed.',
        cause: error,
      );
    }
  }
}
