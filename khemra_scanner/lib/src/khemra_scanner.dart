import 'package:flutter/material.dart';

import 'camera/scanner_camera.dart';
import 'processing/scanner_processor.dart';
import 'result/scanner_result.dart';

/// Public entry point for document scanning.
class KhemraScanner {
  const KhemraScanner._();

  /// Opens the camera, captures one image, and validates it.
  static Future<KhemraScannerResult> scan(
    BuildContext context, {
    ScannerProcessor processor = const ScannerProcessor(),
  }) async {
    final capture = await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ScannerCameraPage()),
    );
    if (capture == null) {
      return const KhemraScannerResult(isValid: false);
    }

    try {
      return await processor.process(capture);
    } on KhemraScannerException {
      rethrow;
    } on Object catch (error) {
      throw KhemraScannerException(
        'The scan could not be completed.',
        cause: error,
      );
    }
  }
}
