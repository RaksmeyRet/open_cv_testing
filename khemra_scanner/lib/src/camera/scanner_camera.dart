import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../capture/scanner_capture.dart';
import '../result/scanner_result.dart';

class ScannerCameraPage extends StatefulWidget {
  const ScannerCameraPage({super.key});

  @override
  State<ScannerCameraPage> createState() => _ScannerCameraPageState();
}

class _ScannerCameraPageState extends State<ScannerCameraPage>
    with WidgetsBindingObserver {
  CameraController? _controller;
  String? _errorMessage;
  bool _isInitializing = true;
  bool _isCapturing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      controller.dispose();
      _controller = null;
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    if (!mounted) return;
    setState(() {
      _isInitializing = true;
      _errorMessage = null;
    });

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw const KhemraScannerException('No camera was found.');
      }
      final backCamera = cameras.where(
        (camera) => camera.lensDirection == CameraLensDirection.back,
      );
      final controller = CameraController(
        backCamera.isNotEmpty ? backCamera.first : cameras.first,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      await _controller?.dispose();
      setState(() {
        _controller = controller;
        _isInitializing = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _isInitializing = false;
        _errorMessage = error is KhemraScannerException
            ? error.message
            : 'Camera access could not be initialized.';
      });
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || _isCapturing) return;

    setState(() => _isCapturing = true);
    try {
      final capture = await const ScannerCapture().capture(controller);
      if (mounted) Navigator.of(context).pop(capture);
    } on KhemraScannerException catch (error) {
      if (mounted) setState(() => _errorMessage = error.message);
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      appBar: AppBar(title: const Text('Scan document')),
      body: _buildBody(controller),
      floatingActionButton: controller == null || _isCapturing
          ? null
          : FloatingActionButton(
              onPressed: _capture,
              tooltip: 'Capture image',
              child: const Icon(Icons.camera_alt),
            ),
    );
  }

  Widget _buildBody(CameraController? controller) {
    if (_isInitializing) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_errorMessage!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _initializeCamera,
              child: const Text('Try again'),
            ),
          ],
        ),
      );
    }
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: Text('Camera is unavailable.'));
    }
    return Center(child: CameraPreview(controller));
  }
}
