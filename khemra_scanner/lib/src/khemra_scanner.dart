import 'package:flutter/material.dart';

import 'camera/scanner_camera.dart';
import 'processing/scanner_processor.dart';
import 'result/scanner_result.dart';
import 'style/scanner_style.dart';

/// Public entry point for document scanning.
class KhemraScanner {
  const KhemraScanner({
    this.processor = const ScannerProcessor(),
    this.style = const KhemraScannerStyle(),
  });

  final ScannerProcessor processor;
  final KhemraScannerStyle style;

  /// Opens the camera, captures one image, and validates it.
  Future<KhemraScannerResult> scan(
    BuildContext context, {
    ScannerProcessor? processor,
    KhemraScannerStyle? style,
  }) async {
    final result = await Navigator.of(context).push<KhemraScannerResult>(
      MaterialPageRoute(
        builder: (_) => ScannerCameraPage(
          processor: processor ?? this.processor,
          style: style ?? this.style,
        ),
      ),
    );
    if (result == null) {
      return const KhemraScannerResult(isValid: false);
    }
    return result;
  }
}
