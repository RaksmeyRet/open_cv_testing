import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';

/// Manages the [CameraController] lifecycle for KhemraScanner.
/// KhemraScanner package.
class ScannerCameraController extends GetxController 
    with WidgetsBindingObserver {
  final isOpeningCamera = false.obs;
  final isPicking = false.obs;
  final showCamera = true.obs;
  final errorMessage = RxnString();

  final Rxn<CameraController> _cameraController = Rxn<CameraController>();
  CameraController? get cameraController => _cameraController.value;

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void onClose() {
    cameraController?.dispose();
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = cameraController;
    if (controller == null || !controller.value.isInitialized) return;
 
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      disposeCamera();
    } else if (state == AppLifecycleState.resumed) {
      openCamera();
    }
  }
  /// Opens the back camera at high resolution.
  Future<void> openCamera() async {
    if (isOpeningCamera.value) return;
    isOpeningCamera.value = true;

    showCamera.value = true;
    errorMessage.value = null;
   
    try {
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        errorMessage.value = 'Camera permission was denied.';
        return;
      }
 
      await disposeCamera();
 
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw Exception('No camera found on this phone.');
 
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
 
      final controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
 
      await controller.initialize();
      _cameraController.value = controller;
    } catch (error) {
      errorMessage.value = 'Camera could not be opened. Please try again.';
      debugPrint('openCamera failed: $error');
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
      errorMessage.value = 'Could not toggle flash.';
      debugPrint('toggleFlash failed: $error');
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
    } catch (error) {
      errorMessage.value = 'Could not take picture.';
      debugPrint('takePicture failed: $error');
      return null;
    } finally {
      isPicking.value = false;
    }
  }
 
  /// Disposes and clears the current [CameraController].
  Future<void> disposeCamera() async {
    final controller = _cameraController.value;
    _cameraController.value = null;
    await controller?.dispose();
  }
}