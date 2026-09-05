import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ScanController extends GetxController {
  final isLoading = false.obs;
  final imagePath = ''.obs;
  final isPicking = false.obs;
  final isOpeningCamera = false.obs;
  final showCamera = true.obs;
  final errorMessage = RxnString();
  final frontImage = Rxn<File>();
  final fieldControllers = <TextEditingController>[].obs;

  CameraController? cameraController;

  @override
  void onInit() {
    super.onInit();
    fieldControllers.assignAll(
      List.generate(5, (_) => TextEditingController()),
    );
  }

  @override
  void onClose() {
    for (final controller in fieldControllers) {
      controller.dispose();
    }
    cameraController?.dispose();
    super.onClose();
  }
}
