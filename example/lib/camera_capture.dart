// import 'dart:async';
// import 'dart:io';
// import 'dart:ui' as ui;

// import 'package:camera/camera.dart';
// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
// import 'package:native_opencv/native_opencv.dart';

// class CameraCaptureScreen extends StatefulWidget {
//   const CameraCaptureScreen({super.key});

//   @override
//   State<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
// }

// class _CameraCaptureScreenState extends State<CameraCaptureScreen>
//     with WidgetsBindingObserver {
//   CameraController? _controller;

//   static const Duration _processThrottle = Duration(milliseconds: 120);

//   bool _isStreaming = false;
//   bool _isProcessing = false;
//   bool _busyWithResult = false;
//   DateTime? _lastProcessedAt;

//   bool _lastIsBlurred = true;

//   Uint8List? _croppedResultRgba;
//   String? _statusMessage;

//   @override
//   void initState() {
//     super.initState();
//     WidgetsBinding.instance.addObserver(this);
//     _enterFullscreenLandscape();
//     _initCamera();
//   }

//   Future<void> _enterFullscreenLandscape() async {
//     await SystemChrome.setPreferredOrientations([
//       DeviceOrientation.landscapeLeft,
//       DeviceOrientation.landscapeRight,
//     ]);
//     await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
//   }

//   Future<void> _initCamera() async {
//     final cameras = await availableCameras();
//     if (cameras.isEmpty) {
//       setState(() => _statusMessage = 'No cameras found on this device.');
//       return;
//     }

//     _controller = CameraController(
//       cameras.first,
//       ResolutionPreset.high,
//       enableAudio: false,
//       imageFormatGroup: ImageFormatGroup.yuv420,
//     );

//     try {
//       await _controller!.initialize();
//     } catch (e) {
//       setState(() => _statusMessage = 'Camera init failed: $e');
//       return;
//     }

//     if (!mounted) return;
//     setState(() {});
//     _startStream();
//   }

//   void _startStream() {
//     if (_controller == null || _isStreaming) return;
//     _isStreaming = true;

//     _controller!.startImageStream((CameraImage image) {
//       final now = DateTime.now();
//       if (_isProcessing || _busyWithResult) return;
//       if (_lastProcessedAt != null &&
//           now.difference(_lastProcessedAt!) < _processThrottle) {
//         return;
//       }
//       _lastProcessedAt = now;
//       _isProcessing = true;
//       _processFrame(image).whenComplete(() => _isProcessing = false);
//     });
//   }

//   Future<void> _stopStream() async {
//     if (_controller == null || !_isStreaming) return;
//     await _controller!.stopImageStream();
//     _isStreaming = false;
//   }

//   Future<void> _processFrame(CameraImage image) async {
//     final rawRgba = _convertCameraImageToRgba(image);
//     if (rawRgba == null) return;

//     final rotated = _applyRotation(rawRgba, image.width, image.height);
//     final rgba = rotated.rgba;
//     final width = rotated.width;
//     final height = rotated.height;

//     final isBlurred = NativeOpencv.isImageBlurred(rgba, width, height);

//     if (!mounted) return;

//     setState(() => _lastIsBlurred = isBlurred);

//     if (!isBlurred) {
//       await _attemptCapture(rgba, width, height);
//     }
//   }

//   // ---------------------------------------------------------------------
//   // Rotation correction
//   // ---------------------------------------------------------------------

//   static const Map<DeviceOrientation, int> _deviceOrientationDegrees = {
//     DeviceOrientation.portraitUp: 0,
//     DeviceOrientation.landscapeLeft: 90,
//     DeviceOrientation.portraitDown: 180,
//     DeviceOrientation.landscapeRight: 270,
//   };

//   /// Degrees the sensor image must be rotated clockwise to appear upright,
//   /// accounting for the sensor's fixed mounting angle AND the device's
//   /// current physical orientation — so this works in portrait or landscape.
//   int get _rotationCompensationDegrees {
//     final controller = _controller;
//     if (controller == null) return 0;

//     final sensorOrientation = controller.description.sensorOrientation;

//     if (Platform.isIOS) return sensorOrientation;

//     final deviceDegrees =
//         _deviceOrientationDegrees[controller.value.deviceOrientation] ?? 0;

//     if (controller.description.lensDirection == CameraLensDirection.front) {
//       return (sensorOrientation + deviceDegrees) % 360;
//     }
//     return (sensorOrientation - deviceDegrees + 360) % 360;
//   }

//   ({Uint8List rgba, int width, int height}) _applyRotation(
//     Uint8List rgba,
//     int width,
//     int height,
//   ) {
//     final degrees = _rotationCompensationDegrees;
//     final swapped = degrees == 90 || degrees == 270;

//     return (
//       rgba: _rotate(rgba, width, height, degrees),
//       width: swapped ? height : width,
//       height: swapped ? width : height,
//     );
//   }

//   Uint8List _rotate(Uint8List src, int width, int height, int degrees) {
//     if (degrees == 0) return src;

//     // Row stride of the output buffer: unchanged for 180°, swapped for 90/270°.
//     final outStride = degrees == 180 ? width : height;
//     final out = Uint8List(width * height * 4);

//     for (int y = 0; y < height; y++) {
//       for (int x = 0; x < width; x++) {
//         final int newX;
//         final int newY;
//         switch (degrees) {
//           case 90:
//             newX = height - 1 - y;
//             newY = x;
//             break;
//           case 270:
//             newX = y;
//             newY = width - 1 - x;
//             break;
//           default: // 180
//             newX = width - 1 - x;
//             newY = height - 1 - y;
//         }

//         final srcIndex = (y * width + x) * 4;
//         final dstIndex = (newY * outStride + newX) * 4;
//         out[dstIndex] = src[srcIndex];
//         out[dstIndex + 1] = src[srcIndex + 1];
//         out[dstIndex + 2] = src[srcIndex + 2];
//         out[dstIndex + 3] = src[srcIndex + 3];
//       }
//     }
//     return out;
//   }

//   Future<void> _attemptCapture(Uint8List rgba, int width, int height) async {
//     await _stopStream();
//     setState(() => _busyWithResult = true);

//     final cropped = NativeOpencv.cropIdCard(rgba, width, height);

//     if (cropped == null) {
//       // No card detected in that frame — keep scanning.
//       setState(() => _busyWithResult = false);
//       _startStream();
//       return;
//     }
//     debugPrint(
//       'Captured ID card resolution: '
//       '${width}x$height',
//     );

//     setState(() => _croppedResultRgba = cropped);
//   }

//   void _retry() {
//     setState(() {
//       _croppedResultRgba = null;
//       _busyWithResult = false;
//     });
//     _startStream();
//   }

//   // ---------------------------------------------------------------------
//   // Pixel format conversion
//   // ---------------------------------------------------------------------

//   Uint8List? _convertCameraImageToRgba(CameraImage image) {
//     try {
//       if (image.planes.length == 1) {
//         return _bgra8888ToRgba(image);
//       }
//       return _yuv420ToRgba(image);
//     } catch (e) {
//       debugPrint('Pixel conversion failed: $e');
//       return null;
//     }
//   }

//   Uint8List _bgra8888ToRgba(CameraImage image) {
//     final bytes = image.planes.first.bytes;
//     final rgba = Uint8List(bytes.length);

//     for (int i = 0; i < bytes.length; i += 4) {
//       rgba[i] = bytes[i + 2]; // R
//       rgba[i + 1] = bytes[i + 1]; // G
//       rgba[i + 2] = bytes[i]; // B
//       rgba[i + 3] = bytes[i + 3]; // A
//     }

//     return rgba;
//   }

//   Uint8List _yuv420ToRgba(CameraImage image) {
//     final int width = image.width;
//     final int height = image.height;

//     final yPlane = image.planes[0];
//     final uPlane = image.planes[1];
//     final vPlane = image.planes[2];

//     final int yRowStride = yPlane.bytesPerRow;
//     final int uvRowStride = uPlane.bytesPerRow;
//     final int uvPixelStride = uPlane.bytesPerPixel ?? 1;

//     final Uint8List rgba = Uint8List(width * height * 4);

//     for (int row = 0; row < height; row++) {
//       final int yRowOffset = row * yRowStride;
//       final int uvRowOffset = (row >> 1) * uvRowStride;

//       for (int col = 0; col < width; col++) {
//         final int yIndex = yRowOffset + col;
//         final int uvIndex = uvRowOffset + (col >> 1) * uvPixelStride;

//         final int yValue = yPlane.bytes[yIndex];
//         final int uValue = uPlane.bytes[uvIndex];
//         final int vValue = vPlane.bytes[uvIndex];

//         final int c = yValue - 16;
//         final int d = uValue - 128;
//         final int e = vValue - 128;

//         int r = (298 * c + 409 * e + 128) >> 8;
//         int g = (298 * c - 100 * d - 208 * e + 128) >> 8;
//         int b = (298 * c + 516 * d + 128) >> 8;

//         r = r.clamp(0, 255);
//         g = g.clamp(0, 255);
//         b = b.clamp(0, 255);

//         final int pixelIndex = (row * width + col) * 4;
//         rgba[pixelIndex] = r;
//         rgba[pixelIndex + 1] = g;
//         rgba[pixelIndex + 2] = b;
//         rgba[pixelIndex + 3] = 255;
//       }
//     }

//     return rgba;
//   }

//   // ---------------------------------------------------------------------
//   // Lifecycle
//   // ---------------------------------------------------------------------

//   @override
//   void didChangeAppLifecycleState(AppLifecycleState state) {
//     final controller = _controller;
//     if (controller == null || !controller.value.isInitialized) return;

//     if (state == AppLifecycleState.inactive) {
//       _stopStream();
//     } else if (state == AppLifecycleState.resumed) {
//       _startStream();
//     }
//   }

//   @override
//   void dispose() {
//     WidgetsBinding.instance.removeObserver(this);
//     _controller?.dispose();
//     SystemChrome.setPreferredOrientations(DeviceOrientation.values);
//     SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
//     super.dispose();
//   }

//   // ---------------------------------------------------------------------
//   // UI
//   // ---------------------------------------------------------------------

//   @override
//   Widget build(BuildContext context) {
//     final controller = _controller;

//     if (_statusMessage != null) {
//       return Scaffold(body: Center(child: Text(_statusMessage!)));
//     }

//     if (controller == null || !controller.value.isInitialized) {
//       return const Scaffold(body: Center(child: CircularProgressIndicator()));
//     }

//     return Scaffold(
//       extendBodyBehindAppBar: true,
//       backgroundColor: Colors.black,
//       appBar: AppBar(
//         backgroundColor: Colors.transparent,
//         elevation: 0,
//         title: const Text('ID Card Capture Test'),
//       ),
//       body:
//           _croppedResultRgba != null
//               ? _buildResultView()
//               : _buildCameraView(controller),
//     );
//   }

//   Widget _buildCameraView(CameraController controller) {
//     return Stack(
//       fit: StackFit.expand,
//       children: [
//         _buildFullscreenPreview(controller),
//         Positioned(
//           top: 30,
//           left: 20,
//           right: 20,
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Text(
//                 _lastIsBlurred ? 'IMAGE IS BLURRY' : 'GOOD IMAGE',
//                 style: TextStyle(
//                   color: _lastIsBlurred ? Colors.red : Colors.green,
//                   fontSize: 20,
//                   fontWeight: FontWeight.bold,
//                   shadows: const [Shadow(blurRadius: 4, color: Colors.black)],
//                 ),
//               ),
//               if (_busyWithResult) ...[
//                 const SizedBox(height: 12),
//                 const CircularProgressIndicator(),
//               ],
//             ],
//           ),
//         ),
//       ],
//     );
//   }

//   Widget _buildFullscreenPreview(CameraController controller) {
//     return Container(
//       color: Colors.black,
//       child: Center(
//         child: AspectRatio(
//           aspectRatio: controller.value.aspectRatio,
//           child: CameraPreview(controller),
//         ),
//       ),
//     );
//   }

//   Widget _buildResultView() {
//     return Column(
//       children: [
//         Expanded(
//           child: Center(
//             child: FutureBuilder<ui.Image>(
//               future: _rgbaToUiImage(
//                 _croppedResultRgba!,
//                 NativeOpencv.idCardOutputWidth,
//                 NativeOpencv.idCardOutputHeight,
//               ),
//               builder: (context, snapshot) {
//                 if (!snapshot.hasData) {
//                   return const CircularProgressIndicator();
//                 }
//                 return RawImage(image: snapshot.data);
//               },
//             ),
//           ),
//         ),
//         Padding(
//           padding: const EdgeInsets.all(16.0),
//           child: Row(
//             mainAxisAlignment: MainAxisAlignment.spaceEvenly,
//             children: [
//               ElevatedButton(onPressed: _retry, child: const Text('Retry')),
//               ElevatedButton(
//                 onPressed: () => Navigator.of(context).pop(_croppedResultRgba),
//                 child: const Text('Use This'),
//               ),
//             ],
//           ),
//         ),
//       ],
//     );
//   }

//   Future<ui.Image> _rgbaToUiImage(Uint8List rgba, int width, int height) {
//     final completer = Completer<ui.Image>();
//     ui.decodeImageFromPixels(
//       rgba,
//       width,
//       height,
//       ui.PixelFormat.rgba8888,
//       completer.complete,
//     );
//     return completer.future;
//   }
// }

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:native_opencv/native_opencv.dart';

class CameraCaptureScreen extends StatefulWidget {
  const CameraCaptureScreen({super.key});

  @override
  State<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends State<CameraCaptureScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;

  static const Duration _processThrottle = Duration(milliseconds: 120);

  bool _isStreaming = false;
  bool _isProcessing = false;
  bool _busyWithResult = false;
  DateTime? _lastProcessedAt;

  bool _lastIsBlurred = true;

  // Latest processed frame, cached so a manual capture tap can use it
  // instead of triggering capture automatically on a sharp frame.
  Uint8List? _pendingRgba;
  int? _pendingWidth;
  int? _pendingHeight;

  Uint8List? _croppedResultRgba;
  String? _statusMessage;

  // OCR
  static const String _ocrBaseUrl = 'http://157.245.49.153:8212';

  bool _isOcrLoading = false;
  Map<String, dynamic>? _ocrResult;
  String? _ocrError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _enterFullscreenLandscape();
    _initCamera();
  }

  Future<void> _enterFullscreenLandscape() async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      setState(() => _statusMessage = 'No cameras found on this device.');
      return;
    }

    _controller = CameraController(
      cameras.first,
      ResolutionPreset.max,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    try {
      await _controller!.initialize();
    } catch (e) {
      setState(() => _statusMessage = 'Camera init failed: $e');
      return;
    }

    if (!mounted) return;
    setState(() {});
    _startStream();
  }

  void _startStream() {
    if (_controller == null || _isStreaming) return;
    _isStreaming = true;

    _controller!.startImageStream((CameraImage image) {
      final now = DateTime.now();
      if (_isProcessing || _busyWithResult) return;
      if (_lastProcessedAt != null &&
          now.difference(_lastProcessedAt!) < _processThrottle) {
        return;
      }
      _lastProcessedAt = now;
      _isProcessing = true;
      _processFrame(image).whenComplete(() => _isProcessing = false);
    });
  }

  Future<void> _stopStream() async {
    if (_controller == null || !_isStreaming) return;
    await _controller!.stopImageStream();
    _isStreaming = false;
  }

  Future<void> _processFrame(CameraImage image) async {
    final rawRgba = _convertCameraImageToRgba(image);
    if (rawRgba == null) return;

    final rotated = _applyRotation(rawRgba, image.width, image.height);
    final rgba = rotated.rgba;
    final width = rotated.width;
    final height = rotated.height;

    final isBlurred = NativeOpencv.isImageBlurred(rgba, width, height);

    if (!mounted) return;

    setState(() => _lastIsBlurred = isBlurred);

    // No auto-capture — just cache the latest processed frame so a manual
    // capture tap has something ready to use.
    _pendingRgba = rgba;
    _pendingWidth = width;
    _pendingHeight = height;
  }

  // ---------------------------------------------------------------------
  // Rotation correction
  // ---------------------------------------------------------------------

  static const Map<DeviceOrientation, int> _deviceOrientationDegrees = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  /// Degrees the sensor image must be rotated clockwise to appear upright,
  /// accounting for the sensor's fixed mounting angle AND the device's
  /// current physical orientation — so this works in portrait or landscape.
  int get _rotationCompensationDegrees {
    final controller = _controller;
    if (controller == null) return 0;

    final sensorOrientation = controller.description.sensorOrientation;

    if (Platform.isIOS) return sensorOrientation;

    final deviceDegrees =
        _deviceOrientationDegrees[controller.value.deviceOrientation] ?? 0;

    if (controller.description.lensDirection == CameraLensDirection.front) {
      return (sensorOrientation + deviceDegrees) % 360;
    }
    return (sensorOrientation - deviceDegrees + 360) % 360;
  }

  ({Uint8List rgba, int width, int height}) _applyRotation(
    Uint8List rgba,
    int width,
    int height,
  ) {
    final degrees = _rotationCompensationDegrees;
    final swapped = degrees == 90 || degrees == 270;

    return (
      rgba: _rotate(rgba, width, height, degrees),
      width: swapped ? height : width,
      height: swapped ? width : height,
    );
  }

  Uint8List _rotate(Uint8List src, int width, int height, int degrees) {
    if (degrees == 0) return src;

    // Row stride of the output buffer: unchanged for 180°, swapped for 90/270°.
    final outStride = degrees == 180 ? width : height;
    final out = Uint8List(width * height * 4);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final int newX;
        final int newY;
        switch (degrees) {
          case 90:
            newX = height - 1 - y;
            newY = x;
            break;
          case 270:
            newX = y;
            newY = width - 1 - x;
            break;
          default: // 180
            newX = width - 1 - x;
            newY = height - 1 - y;
        }

        final srcIndex = (y * width + x) * 4;
        final dstIndex = (newY * outStride + newX) * 4;
        out[dstIndex] = src[srcIndex];
        out[dstIndex + 1] = src[srcIndex + 1];
        out[dstIndex + 2] = src[srcIndex + 2];
        out[dstIndex + 3] = src[srcIndex + 3];
      }
    }
    return out;
  }

  // ---------------------------------------------------------------------
  // Manual capture
  // ---------------------------------------------------------------------

  Future<void> _onCapturePressed() async {
    if (_busyWithResult) return;

    final rgba = _pendingRgba;
    final width = _pendingWidth;
    final height = _pendingHeight;
    if (rgba == null || width == null || height == null) return;

    await _attemptCapture(rgba, width, height);
  }

  Future<void> _attemptCapture(Uint8List rgba, int width, int height) async {
    await _stopStream();
    setState(() => _busyWithResult = true);

    final cropped = NativeOpencv.cropIdCard(rgba, width, height);

    if (cropped == null) {
      // No card detected in that frame — keep scanning.
      setState(() => _busyWithResult = false);
      _startStream();
      return;
    }
    debugPrint(
      'Captured ID card resolution: '
      '${width}x$height',
    );

    setState(() => _croppedResultRgba = cropped);
    unawaited(_runOcr(cropped));
  }

  void _retry() {
    setState(() {
      _croppedResultRgba = null;
      _busyWithResult = false;
      _isOcrLoading = false;
      _ocrResult = null;
      _ocrError = null;
    });
    _startStream();
  }

  // ---------------------------------------------------------------------
  // OCR
  // ---------------------------------------------------------------------

  Future<Uint8List> _encodePngBytes(
    Uint8List rgba,
    int width,
    int height,
  ) async {
    final image = await _rgbaToUiImage(rgba, width, height);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  Future<void> _runOcr(Uint8List croppedRgba) async {
    setState(() {
      _isOcrLoading = true;
      _ocrError = null;
      _ocrResult = null;
    });

    try {
      final pngBytes = await _encodePngBytes(
        croppedRgba,
        NativeOpencv.idCardOutputWidth,
        NativeOpencv.idCardOutputHeight,
      );

      final uri = Uri.parse('$_ocrBaseUrl/api/ocr/id-card/');
      final request =
          http.MultipartRequest('POST', uri)
            ..fields['language'] = 'eng+khm'
            ..files.add(
              http.MultipartFile.fromBytes(
                'file',
                pngBytes,
                filename: 'id_card.png',
              ),
            );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        setState(() {
          _ocrResult = decoded;
          _isOcrLoading = false;
        });
      } else {
        setState(() {
          _ocrError = 'OCR failed (HTTP ${response.statusCode})';
          _isOcrLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _ocrError = 'OCR request failed: $e';
        _isOcrLoading = false;
      });
    }
  }

  // ---------------------------------------------------------------------
  // Pixel format conversion
  // ---------------------------------------------------------------------

  Uint8List? _convertCameraImageToRgba(CameraImage image) {
    try {
      if (image.planes.length == 1) {
        return _bgra8888ToRgba(image);
      }
      return _yuv420ToRgba(image);
    } catch (e) {
      debugPrint('Pixel conversion failed: $e');
      return null;
    }
  }

  Uint8List _bgra8888ToRgba(CameraImage image) {
    final bytes = image.planes.first.bytes;
    final rgba = Uint8List(bytes.length);

    for (int i = 0; i < bytes.length; i += 4) {
      rgba[i] = bytes[i + 2]; // R
      rgba[i + 1] = bytes[i + 1]; // G
      rgba[i + 2] = bytes[i]; // B
      rgba[i + 3] = bytes[i + 3]; // A
    }

    return rgba;
  }

  Uint8List _yuv420ToRgba(CameraImage image) {
    final int width = image.width;
    final int height = image.height;

    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final int yRowStride = yPlane.bytesPerRow;
    final int uvRowStride = uPlane.bytesPerRow;
    final int uvPixelStride = uPlane.bytesPerPixel ?? 1;

    final Uint8List rgba = Uint8List(width * height * 4);

    for (int row = 0; row < height; row++) {
      final int yRowOffset = row * yRowStride;
      final int uvRowOffset = (row >> 1) * uvRowStride;

      for (int col = 0; col < width; col++) {
        final int yIndex = yRowOffset + col;
        final int uvIndex = uvRowOffset + (col >> 1) * uvPixelStride;

        final int yValue = yPlane.bytes[yIndex];
        final int uValue = uPlane.bytes[uvIndex];
        final int vValue = vPlane.bytes[uvIndex];

        final int c = yValue - 16;
        final int d = uValue - 128;
        final int e = vValue - 128;

        int r = (298 * c + 409 * e + 128) >> 8;
        int g = (298 * c - 100 * d - 208 * e + 128) >> 8;
        int b = (298 * c + 516 * d + 128) >> 8;

        r = r.clamp(0, 255);
        g = g.clamp(0, 255);
        b = b.clamp(0, 255);

        final int pixelIndex = (row * width + col) * 4;
        rgba[pixelIndex] = r;
        rgba[pixelIndex + 1] = g;
        rgba[pixelIndex + 2] = b;
        rgba[pixelIndex + 3] = 255;
      }
    }

    return rgba;
  }

  // ---------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      _stopStream();
    } else if (state == AppLifecycleState.resumed) {
      _startStream();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    if (_statusMessage != null) {
      return Scaffold(body: Center(child: Text(_statusMessage!)));
    }

    if (controller == null || !controller.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('ID Card Capture Test'),
      ),
      body:
          _croppedResultRgba != null
              ? _buildResultView()
              : _buildCameraView(controller),
    );
  }

  Widget _buildCameraView(CameraController controller) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildFullscreenPreview(controller),
        Positioned(
          top: 30,
          left: 20,
          right: 20,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _lastIsBlurred ? 'IMAGE IS BLURRY' : 'GOOD IMAGE',
                style: TextStyle(
                  color: _lastIsBlurred ? Colors.red : Colors.green,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  shadows: const [Shadow(blurRadius: 4, color: Colors.black)],
                ),
              ),
              if (_busyWithResult) ...[
                const SizedBox(height: 12),
                const CircularProgressIndicator(),
              ],
            ],
          ),
        ),
        Positioned(
          bottom: 40,
          left: 0,
          right: 0,
          child: Center(
            child: GestureDetector(
              onTap: _busyWithResult ? null : _onCapturePressed,
              child: Container(
                width: 74,
                height: 74,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 4),
                ),
                padding: const EdgeInsets.all(4),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _busyWithResult ? Colors.white38 : Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFullscreenPreview(CameraController controller) {
    return Container(
      color: Colors.black,
      child: Center(
        child: AspectRatio(
          aspectRatio: controller.value.aspectRatio,
          child: CameraPreview(controller),
        ),
      ),
    );
  }

  Widget _buildResultView() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                SizedBox(
                  height: 220,
                  child: FutureBuilder<ui.Image>(
                    future: _rgbaToUiImage(
                      _croppedResultRgba!,
                      NativeOpencv.idCardOutputWidth,
                      NativeOpencv.idCardOutputHeight,
                    ),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      return RawImage(image: snapshot.data);
                    },
                  ),
                ),
                const SizedBox(height: 20),
                _buildOcrSection(),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton(onPressed: _retry, child: const Text('Retry')),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(_croppedResultRgba),
                child: const Text('Use This'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOcrSection() {
    if (_isOcrLoading) {
      return const Column(
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 12),
          Text('Extracting text...', style: TextStyle(color: Colors.white)),
        ],
      );
    }

    if (_ocrError != null) {
      return Column(
        children: [
          Text(_ocrError!, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () => _runOcr(_croppedResultRgba!),
            child: const Text('Retry OCR'),
          ),
        ],
      );
    }

    final result = _ocrResult;
    if (result == null) return const SizedBox.shrink();

    final fields = (result['fields'] as Map<String, dynamic>?) ?? {};
    final confidence = result['confidence'];

    return Card(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (confidence != null)
              Text(
                'Confidence: ${((confidence as num) * 100).toStringAsFixed(1)}%',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            const SizedBox(height: 8),
            ...fields.entries.map(
              (e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 120,
                      child: Text(
                        e.key,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Expanded(child: Text('${e.value ?? '-'}')),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<ui.Image> _rgbaToUiImage(Uint8List rgba, int width, int height) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      width,
      height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }
}
