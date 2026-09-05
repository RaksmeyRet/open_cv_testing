import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// GetX controller that manages a [CameraController] lifecycle for the
/// KhemraScanner package.
class ScannerCameraController extends GetxController {
  final isOpeningCamera = false.obs;
  final isPicking = false.obs;
  final showCamera = true.obs;
  final errorMessage = RxnString();

  CameraController? cameraController;

  @override
  void onClose() {
    cameraController?.dispose();
    super.onClose();
  }

  /// Opens the back-facing camera and initialises [cameraController].
  ///
  /// Resolves the best available back camera at [ResolutionPreset.high].
  Future<void> openCamera() async {
    if (isOpeningCamera.value) return;
    isOpeningCamera.value = true;

    final previousController = cameraController;
    showCamera.value = true;
    errorMessage.value = null;
    cameraController = null;

    try {
      await previousController?.dispose();

      final cameras = await availableCameras();
      if (cameras.isEmpty) throw Exception('No camera found on this phone.');

      final back = cameras.where(
        (c) => c.lensDirection == CameraLensDirection.back,
      );

      final controller = CameraController(
        back.isNotEmpty ? back.first : cameras.first,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await controller.initialize();
      cameraController = controller;
    } catch (error) {
      errorMessage.value = 'Camera could not be opened: $error';
    } finally {
      isOpeningCamera.value = false;
    }
  }

  /// Toggles the flash/torch mode on the current camera.
  Future<void> toggleFlash() async {
    final controller = cameraController;
    if (controller == null || !controller.value.isInitialized) return;

    try {
      final nextMode = controller.value.flashMode == FlashMode.torch
          ? FlashMode.off
          : FlashMode.torch;
      await controller.setFlashMode(nextMode);
    } catch (error) {
      debugPrint('Flashlight toggle failed: $error');
    }
  }

  /// Takes a picture and returns the captured [XFile].
  Future<XFile?> takePicture() async {
    final controller = cameraController;
    if (controller == null ||
        !controller.value.isInitialized ||
        isPicking.value) {
      return null;
    }
    isPicking.value = true;
    try {
      return await controller.takePicture();
    } finally {
      isPicking.value = false;
    }
  }

  /// Disposes and clears the current [CameraController].
  Future<void> disposeCamera() async {
    final controller = cameraController;
    cameraController = null;
    await controller?.dispose();
  }
}
