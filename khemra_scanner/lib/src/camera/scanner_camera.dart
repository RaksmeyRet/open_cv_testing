import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as image_lib;
import 'package:path_provider/path_provider.dart';

import '../capture/scanner_capture.dart';
import '../processing/scanner_processor.dart';
import '../result/scanner_result.dart';

class ScannerCameraPage extends StatefulWidget {
  const ScannerCameraPage({required this.processor, super.key});

  final ScannerProcessor processor;

  @override
  State<ScannerCameraPage> createState() => _ScannerCameraPageState();
}

class _ScannerCameraPageState extends State<ScannerCameraPage>
    with WidgetsBindingObserver {
  static const _throttle = Duration(milliseconds: 120);
  CameraController? _controller;
  Uint8List? _pendingRgba;
  int? _pendingWidth;
  int? _pendingHeight;
  Uint8List? _resultBytes;
  String? _resultPath;
  String? _errorMessage;
  DateTime? _lastProcessedAt;
  bool _initializing = true;
  bool _streaming = false;
  bool _processing = false;
  bool _capturing = false;
  bool _blurred = true;
  bool _showResult = false;

  ScannerEngine? get _engine => widget.processor.engine;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    if (!mounted) return;
    setState(() {
      _initializing = true;
      _errorMessage = null;
    });
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw const KhemraScannerException('No camera was found.');
      }
      final back = cameras.where(
        (camera) => camera.lensDirection == CameraLensDirection.back,
      );
      final controller = CameraController(
        back.isNotEmpty ? back.first : cameras.first,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: _engine == null
            ? ImageFormatGroup.jpeg
            : ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      await _controller?.dispose();
      setState(() {
        _controller = controller;
        _initializing = false;
      });
      if (_engine != null) _startStream();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _errorMessage = error is KhemraScannerException
            ? error.message
            : 'Camera access could not be initialized.';
      });
    }
  }

  void _startStream() {
    final controller = _controller;
    if (controller == null || _streaming || !controller.value.isInitialized) {
      return;
    }
    _streaming = true;
    controller.startImageStream((image) {
      if (_processing || _showResult) return;
      final now = DateTime.now();
      if (_lastProcessedAt != null &&
          now.difference(_lastProcessedAt!) < _throttle) {
        return;
      }
      _lastProcessedAt = now;
      _processing = true;
      unawaited(_processFrame(image).whenComplete(() => _processing = false));
    }).catchError((Object error) {
      _streaming = false;
      if (mounted) setState(() => _errorMessage = 'Camera stream failed: $error');
    });
  }

  Future<void> _stopStream() async {
    if (_controller == null || !_streaming) return;
    await _controller!.stopImageStream();
    _streaming = false;
  }

  Future<void> _processFrame(CameraImage image) async {
    final raw = _convertCameraImageToRgba(image);
    if (raw == null || _engine == null) return;
    final rotated = _applyRotation(raw, image.width, image.height);
    final blurred = _engine!.isFrameBlurred(
      rotated.rgba,
      rotated.width,
      rotated.height,
    );
    if (!mounted) return;
    setState(() => _blurred = blurred);
    _pendingRgba = rotated.rgba;
    _pendingWidth = rotated.width;
    _pendingHeight = rotated.height;
  }

  Future<void> _capture() async {
    if (_capturing) return;
    setState(() => _capturing = true);
    try {
      final controller = _controller;
      if (controller == null) return;
      if (_engine == null) {
        final capture = await const ScannerCapture().capture(controller);
        final result = await widget.processor.process(capture);
        if (mounted) Navigator.of(context).pop(result);
        return;
      }
      final rgba = _pendingRgba;
      final width = _pendingWidth;
      final height = _pendingHeight;
      if (rgba == null || width == null || height == null) return;
      await _stopStream();
      final cropped = _engine!.cropDocument(rgba, width, height);
      if (cropped == null) {
        _startStream();
        return;
      }
      final path = await _writeImage(cropped);
      if (!mounted) return;
      setState(() {
        _resultBytes = cropped.rgbaBytes;
        _resultPath = path;
        _showResult = true;
      });
    } on KhemraScannerException catch (error) {
      if (mounted) setState(() => _errorMessage = error.message);
    } on Object catch (error) {
      if (mounted) setState(() => _errorMessage = 'Could not capture image: $error');
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<String> _writeImage(ScannerProcessedImage image) async {
    final decoded = image_lib.Image.fromBytes(
      width: image.width,
      height: image.height,
      bytes: image.rgbaBytes.buffer,
      order: image_lib.ChannelOrder.rgba,
    );
    final bytes = Uint8List.fromList(image_lib.encodeJpg(decoded, quality: 92));
    final directory = await getTemporaryDirectory();
    final file = File(
      '${directory.path}/khemra_scan_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  void _retry() {
    setState(() {
      _showResult = false;
      _resultBytes = null;
      _resultPath = null;
    });
    _startStream();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      _stopStream();
    } else if (state == AppLifecycleState.resumed && !_showResult) {
      _startStream();
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
    if (_initializing) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_errorMessage != null) {
      return Scaffold(body: Center(child: Text(_errorMessage!)));
    }
    if (_showResult && _resultPath != null) return _buildResult();
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('ID Card Capture'),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (controller != null) Center(child: CameraPreview(controller)),
          Positioned(
            top: 20,
            left: 20,
            child: Text(
              _engine == null
                  ? 'READY'
                  : (_blurred ? 'IMAGE IS BLURRY' : 'GOOD IMAGE'),
              style: TextStyle(
                color: _engine == null || !_blurred ? Colors.green : Colors.red,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Positioned(
            bottom: 36,
            left: 0,
            right: 0,
            child: Center(
              child: FloatingActionButton(
                onPressed: _capturing ? null : _capture,
                child: const Icon(Icons.camera_alt),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResult() {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan result')),
      body: Column(
        children: [
          Expanded(child: Center(child: Image.file(File(_resultPath!)))),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                OutlinedButton(onPressed: _retry, child: const Text('Retry')),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(
                    KhemraScannerResult(
                      imagePath: _resultPath,
                      isValid: true,
                      imageBytes: _resultBytes,
                    ),
                  ),
                  child: const Text('Use image'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Uint8List? _convertCameraImageToRgba(CameraImage image) {
    try {
      if (image.planes.length == 1) return _bgra8888ToRgba(image);
      return _yuv420ToRgba(image);
    } on Object {
      return null;
    }
  }

  Uint8List _bgra8888ToRgba(CameraImage image) {
    final bytes = image.planes.first.bytes;
    final rgba = Uint8List(bytes.length);
    for (var i = 0; i < bytes.length; i += 4) {
      rgba[i] = bytes[i + 2];
      rgba[i + 1] = bytes[i + 1];
      rgba[i + 2] = bytes[i];
      rgba[i + 3] = bytes[i + 3];
    }
    return rgba;
  }

  Uint8List _yuv420ToRgba(CameraImage image) {
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];
    final rgba = Uint8List(image.width * image.height * 4);
    final uvPixelStride = uPlane.bytesPerPixel ?? 1;
    for (var row = 0; row < image.height; row++) {
      for (var col = 0; col < image.width; col++) {
        final y = yPlane.bytes[row * yPlane.bytesPerRow + col] - 16;
        final uv = (row >> 1) * uPlane.bytesPerRow +
            (col >> 1) * uvPixelStride;
        final d = uPlane.bytes[uv] - 128;
        final e = vPlane.bytes[uv] - 128;
        final index = (row * image.width + col) * 4;
        rgba[index] = ((298 * y + 409 * e + 128) >> 8).clamp(0, 255);
        rgba[index + 1] = ((298 * y - 100 * d - 208 * e + 128) >> 8).clamp(0, 255);
        rgba[index + 2] = ((298 * y + 516 * d + 128) >> 8).clamp(0, 255);
        rgba[index + 3] = 255;
      }
    }
    return rgba;
  }

  ({Uint8List rgba, int width, int height}) _applyRotation(
    Uint8List rgba,
    int width,
    int height,
  ) {
    final controller = _controller!;
    final sensor = controller.description.sensorOrientation;
    final device = <DeviceOrientation, int>{
      DeviceOrientation.portraitUp: 0,
      DeviceOrientation.landscapeLeft: 90,
      DeviceOrientation.portraitDown: 180,
      DeviceOrientation.landscapeRight: 270,
    }[controller.value.deviceOrientation] ?? 0;
    final degrees = Platform.isIOS
        ? sensor
        : (controller.description.lensDirection == CameraLensDirection.front
              ? sensor + device
              : sensor - device + 360) % 360;
    if (degrees == 0) return (rgba: rgba, width: width, height: height);
    final swapped = degrees == 90 || degrees == 270;
    final stride = degrees == 180 ? width : height;
    final output = Uint8List(rgba.length);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final nx = degrees == 90
            ? height - 1 - y
            : degrees == 270
                ? y
                : width - 1 - x;
        final ny = degrees == 90
            ? x
            : degrees == 270
                ? width - 1 - x
                : height - 1 - y;
        final source = (y * width + x) * 4;
        final target = (ny * stride + nx) * 4;
        output.setRange(target, target + 4, rgba, source);
      }
    }
    return (
      rgba: output,
      width: swapped ? height : width,
      height: swapped ? width : height,
    );
  }
}
