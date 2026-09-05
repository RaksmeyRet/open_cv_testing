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
    final result = await Navigator.of(context).push<KhemraScannerResult>(
      MaterialPageRoute(
        builder: (_) => ScannerCameraPage(processor: processor),
      ),
    );
    if (result == null) {
      return const KhemraScannerResult(isValid: false);
    }
    return result;
  }
}
