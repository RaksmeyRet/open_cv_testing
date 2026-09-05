import 'package:camera/camera.dart';

import '../result/scanner_result.dart';

/// Captures a still image from an initialized camera.
class ScannerCapture {
  const ScannerCapture();

  Future<XFile> capture(CameraController controller) async {
    if (!controller.value.isInitialized) {
      throw const KhemraScannerException('The camera is not initialized.');
    }
    if (controller.value.isTakingPicture) {
      throw const KhemraScannerException('The camera is already capturing.');
    }

    try {
      return await controller.takePicture();
    } on CameraException catch (error) {
      throw KhemraScannerException(
        'The image could not be captured.',
        cause: error,
      );
    }
  }
}
