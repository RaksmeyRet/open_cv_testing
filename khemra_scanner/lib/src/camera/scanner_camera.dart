import 'package:camera/camera.dart';
import 'package:flutter/material.dart';


class ScannerCameraPreview extends StatelessWidget {
  const ScannerCameraPreview({required this.controller, super.key});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AspectRatio(
        aspectRatio: 1 / controller.value.aspectRatio,
        child: CameraPreview(controller),
      ),
    );
  }
}
