import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:image/image.dart' as image_lib;

import '../result/scanner_result.dart';

typedef ScannerImageValidator = bool Function(
  Uint8List rgbaBytes,
  int width,
  int height,
);

/// Native or Dart implementation used by the scanner for document checks.
abstract interface class ScannerEngine {
  factory ScannerEngine({
    required ScannerBlurChecker isFrameBlurred,
    required ScannerDocumentCropper cropDocument,
  }) = _CallbackScannerEngine;

  bool isFrameBlurred(Uint8List rgbaBytes, int width, int height);

  ScannerProcessedImage? cropDocument(
    Uint8List rgbaBytes,
    int width,
    int height,
  );
}

typedef ScannerBlurChecker = bool Function(
  Uint8List rgbaBytes,
  int width,
  int height,
);

typedef ScannerDocumentCropper = ScannerProcessedImage? Function(
  Uint8List rgbaBytes,
  int width,
  int height,
);

class _CallbackScannerEngine implements ScannerEngine {
  const _CallbackScannerEngine({
    required ScannerBlurChecker isFrameBlurred,
    required ScannerDocumentCropper cropDocument,
  }) : _isFrameBlurred = isFrameBlurred,
       _cropDocument = cropDocument;

  final ScannerBlurChecker _isFrameBlurred;
  final ScannerDocumentCropper _cropDocument;

  @override
  bool isFrameBlurred(Uint8List rgbaBytes, int width, int height) {
    return _isFrameBlurred(rgbaBytes, width, height);
  }

  @override
  ScannerProcessedImage? cropDocument(
    Uint8List rgbaBytes,
    int width,
    int height,
  ) {
    return _cropDocument(rgbaBytes, width, height);
  }
}

class ScannerProcessedImage {
  final Uint8List rgbaBytes;
  final int width;
  final int height;

  const ScannerProcessedImage({
    required this.rgbaBytes,
    required this.width,
    required this.height,
  });
}

/// Processes a captured image without exposing native implementation details.
class ScannerProcessor {
  final ScannerImageValidator? validator;
  final ScannerEngine? engine;

  const ScannerProcessor({this.validator, this.engine});

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
      final isBlurred = engine?.isFrameBlurred(
            rgba,
            decoded.width,
            decoded.height,
          ) ??
          false;
      final isValid = validator?.call(rgba, decoded.width, decoded.height) ??
          !isBlurred;
      if (!isValid || isBlurred) {
        return KhemraScannerResult(imagePath: capture.path, isValid: false);
      }

      final cropped = engine?.cropDocument(
        rgba,
        decoded.width,
        decoded.height,
      );

      return KhemraScannerResult(
        imagePath: capture.path,
        isValid: cropped != null || engine == null,
        imageBytes: cropped?.rgbaBytes,
      );
    } on Object catch (error) {
      throw KhemraScannerException(
        'The captured image could not be processed.',
        cause: error,
      );
    }
  }
}
