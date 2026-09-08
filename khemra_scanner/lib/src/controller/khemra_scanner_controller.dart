import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../image/image_cropper.dart';
import '../models/khemra_scan_result.dart';
import '../ocr/ocr_service.dart';
import '../utils/scanner_utils.dart';

class KhemraScannerController extends GetxController
    with GetSingleTickerProviderStateMixin {
  // ---------------------------------------------------------------------------
  // Text controllers — one per field
  // ---------------------------------------------------------------------------

  final idNumberController = TextEditingController();
  final fullnameEnController = TextEditingController();
  final fullnameKHController = TextEditingController();
  final dateOfBirthController = TextEditingController();
  final expiryDateController = TextEditingController();
  final genderController = TextEditingController();
  final nationalityController = TextEditingController();
  final address = TextEditingController();

  // ---------------------------------------------------------------------------
  // Observable state
  // ---------------------------------------------------------------------------

  final frontImage = Rxn<File>();
  final cameraCtrl = Rxn<CameraController>();
  final showCamera = true.obs;
  final isPicking = false.obs;
  final errorMessage = RxnString();

  /// Bumped on every field change — lets Obx track form validity.
  final _formTick = 0.obs;

  // ---------------------------------------------------------------------------
  // Animation (loading spinner in the preview)
  // ---------------------------------------------------------------------------

  late final AnimationController reloadAnimController;

  // ---------------------------------------------------------------------------
  // Services / config
  // ---------------------------------------------------------------------------
  final _ocrService = OcrService();
  final _isOpeningCamera = false.obs;
  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void onInit() {
    super.onInit();
    reloadAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();

    idNumberController.addListener(_onFieldChanged);
    fullnameEnController.addListener(_onFieldChanged);
    dateOfBirthController.addListener(_onFieldChanged);
    expiryDateController.addListener(_onFieldChanged);
    genderController.addListener(_onFieldChanged);

    openCamera();
  }

  @override
  void onClose() {
    reloadAnimController.dispose();
    cameraCtrl.value?.dispose();

    idNumberController.dispose();
    fullnameEnController.dispose();
    dateOfBirthController.dispose();
    expiryDateController.dispose();
    genderController.dispose();

    super.onClose();
  }

  // ---------------------------------------------------------------------------
  // Camera
  // ---------------------------------------------------------------------------
  Future<void> openCamera() async {
    if (_isOpeningCamera.value) return;
    _isOpeningCamera.value = true;

    try {
      final previous = cameraCtrl.value;
      cameraCtrl.value = null;
      showCamera.value = true;
      errorMessage.value = null;
      await previous?.dispose();

      final cameras = await availableCameras();
      if (cameras.isEmpty) throw Exception('No camera found on this phone.');
      final back = cameras.where(
        (c) => c.lensDirection == CameraLensDirection.back,
      );
      final selected = back.isNotEmpty ? back.first : cameras.first;

      final newController = CameraController(
        selected,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await newController.initialize();

      if (!Get.isRegistered<KhemraScannerController>()) {
        await newController.dispose();
        return;
      }

      cameraCtrl.value = newController;
    } catch (error) {
      errorMessage.value = 'Camera could not be opened: $error';
    } finally {
      _isOpeningCamera.value = false;
    }
  }

  Future<void> takePhoto() async {
    final camera = cameraCtrl.value;
    if (camera == null || !camera.value.isInitialized || isPicking.value) {
      return;
    }

    isPicking.value = true;
    try {
      final photo = await camera.takePicture();
      final capturedFile = File(photo.path);

      cameraCtrl.value = null;
      await camera.dispose();

      final croppedFile = await _navigateToCropper(capturedFile);
      if (croppedFile == null) {
        await openCamera();
        return;
      }

      frontImage.value = croppedFile;
      showCamera.value = false;
      await _runOcr(croppedFile);
    } catch (error) {
      errorMessage.value = 'Could not take photo: $error';
    } finally {
      isPicking.value = false;
    }
  }

  Future<void> toggleFlash() async {
    final camera = cameraCtrl.value;
    if (camera == null || !camera.value.isInitialized || isPicking.value) {
      return;
    }
    try {
      final next = camera.value.flashMode == FlashMode.torch
          ? FlashMode.off
          : FlashMode.torch;
      await camera.setFlashMode(next);
      cameraCtrl.refresh();
    } catch (error) {
      errorMessage.value = 'Flashlight is not available: $error';
    }
  }

  Future<void> openGallery(Future<File?> Function() pickImage) async {
    if (showCamera.value) {
      final camera = cameraCtrl.value;
      cameraCtrl.value = null;
      showCamera.value = false;
      await camera?.dispose();
    }

    final imageFile = await pickImage();
    if (imageFile == null) return;

    final croppedFile = await _navigateToCropper(imageFile);
    if (croppedFile == null) {
      await openCamera();
      return;
    }

    frontImage.value = croppedFile;
    errorMessage.value = null;
    showCamera.value = false;
    await _runOcr(croppedFile);
  }

  void closeAndPop() {
    final camera = cameraCtrl.value;
    cameraCtrl.value = null;
    camera?.dispose();
    Get.back();
  }

  Future<File?> _navigateToCropper(File source) async =>
      Get.to<File>(() => KhemraImageCropperScreen(source: source));

  // ---------------------------------------------------------------------------
  // OCR
  // ---------------------------------------------------------------------------

  Future<void> _runOcr(File imageFile) async {
    isPicking.value = true;
    errorMessage.value = null;

    try {
      final response = await _ocrService.recognize(imageFile);

      if (!Get.isRegistered<KhemraScannerController>()) return;

      final fields = response.khemraScanResult;
      if (fields == null) {
        errorMessage.value = 'Could not read the ID card. Please try again.';
        return;
      }
      idNumberController.text = fields.idNumber ?? '';
      fullnameEnController.text = fields.fullNameEN ?? '';
      fullnameKHController.text = fields.fullnameKH ?? '';
      dateOfBirthController.text = fields.dateOfBirth ?? '';
      expiryDateController.text = fields.expiryDate ?? '';
      genderController.text = fields.gender ?? '';
      nationalityController.text = fields.nationality ?? '';
      address.text = fields.address ?? '';
    } catch (error) {
      if (!Get.isRegistered<KhemraScannerController>()) return;
      errorMessage.value = 'OCR failed: $error';
    } finally {
      isPicking.value = false;
    }
  }


  // ---------------------------------------------------------------------------
  // Form / confirm
  // ---------------------------------------------------------------------------

  bool get isFormValid {
    // Read _formTick so Obx knows to re-evaluate when any field changes.
    _formTick.value;

    return ScannerUtils.fieldValidationError(0, idNumberController.text) ==
            null &&
        ScannerUtils.fieldValidationError(1, fullnameEnController.text) ==
            null &&
        ScannerUtils.fieldValidationError(2, dateOfBirthController.text) ==
            null &&
        ScannerUtils.fieldValidationError(3, expiryDateController.text) ==
            null &&
        ScannerUtils.fieldValidationError(4, genderController.text) == null;
  }

  void confirm() {
    if (!isFormValid) return;
    Get.back(
      result: KhemraScanResult(
        idNumber: idNumberController.text.trim(),
        fullNameEN: fullnameEnController.text.trim(),
        dateOfBirth: dateOfBirthController.text.trim(),
        expiryDate: expiryDateController.text.trim(),
        gender: genderController.text.trim(),
      ),
    );
  }

  void _onFieldChanged() => _formTick.value++;
}
