import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

import 'four_corner_crop_screen.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final ImagePicker _picker = ImagePicker();
  final List<TextEditingController> _controllers = List.generate(
    5,
    (_) => TextEditingController(),
  );

  File? _selectedImage;
  bool _isPicking = false;
  bool _hasCroppedImage = false;
  bool _showCamera = false;
  CameraController? _cameraController;
  String? _errorMessage;

  static const String _ocrBaseUrl = 'http://157.245.49.153:8212';

  static const List<String> _fieldLabels = [
    'ID number',
    'Name',
    'Date of birth',
    'Expiry date',
    'Gender',
  ];

  @override
  void dispose() {
    _cameraController?.dispose();
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _showCamera = true;
    _openCamera();
  }

  Future<void> _openCamera() async {
    setState(() {
      _showCamera = true;
      _errorMessage = null;
    });

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw Exception('No camera found on this phone.');
      final controller = CameraController(
        cameras.first,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _cameraController = controller);
    } catch (error) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Camera could not be opened: $error';
        });
      }
    }
  }

  Future<void> _takePhoto() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized || _isPicking) {
      return;
    }
    setState(() => _isPicking = true);
    try {
      final photo = await controller.takePicture();
      if (mounted) {
        setState(() {
          _cameraController = null;
          _showCamera = false;
          _selectedImage = File(photo.path);
          _hasCroppedImage = false;
        });
      }
      await controller.dispose();
    } catch (error) {
      if (mounted) {
        setState(() => _errorMessage = 'Could not take photo: $error');
      }
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  Future<void> _openGallery() async {
    if (_showCamera) {
      final controller = _cameraController;
      _cameraController = null;
      if (mounted) setState(() => _showCamera = false);
      await controller?.dispose();
    }
    await _pickImage(ImageSource.gallery);
  }

  Future<void> _pickImage(ImageSource source) async {
    setState(() {
      _isPicking = true;
      _errorMessage = null;
    });

    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 90,
        maxWidth: 2400,
      );
      if (picked == null) return;

      if (mounted) {
        setState(() {
          _selectedImage = File(picked.path);
          _hasCroppedImage = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _errorMessage = 'Could not open the image: $error');
      }
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  Future<void> _editCrop() async {
    final image = _selectedImage;
    if (image == null || _isPicking) return;

    setState(() => _isPicking = true);
    try {
      final cropped = await Navigator.of(context).push<File>(
        MaterialPageRoute(builder: (_) => FourCornerCropScreen(source: image)),
      );
      if (cropped == null || !mounted) return;
      setState(() {
        _selectedImage = cropped;
        _hasCroppedImage = true;
        _errorMessage = null;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _errorMessage = 'Could not open crop editor: $error');
      }
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  Future<bool> _runOcr(File imageFile) async {
    setState(() {
      _errorMessage = null;
    });

    try {
      final request =
          http.MultipartRequest(
              'POST',
              Uri.parse('$_ocrBaseUrl/api/ocr/id-card/'),
            )
            ..fields['language'] = 'eng+khm'
            ..files.add(
              await http.MultipartFile.fromPath('file', imageFile.path),
            );
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode != 200) {
        throw Exception('OCR failed (HTTP ${response.statusCode})');
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final fields = (decoded['fields'] as Map?)?.map(
        (key, value) => MapEntry(_normalizeKey('$key'), '$value'),
      );
      if (fields == null) throw Exception('OCR response has no fields');

      for (var index = 0; index < _fieldLabels.length; index++) {
        _controllers[index].text = _fieldValue(fields, index);
      }
      return true;
    } catch (error) {
      if (mounted) {
        setState(
          () => _errorMessage = 'Could not read text from image: $error',
        );
      }
    }
    return false;
  }

  String _fieldValue(Map<String, String> fields, int index) {
    const keys = [
      ['idnumber', 'idno', 'id'],
      ['name', 'fullname', 'full_name'],
      ['dateofbirth', 'dob', 'birthdate'],
      ['expirydate', 'expiry', 'expirationdate'],
      ['gender', 'sex'],
    ];
    for (final key in keys[index]) {
      final value = fields[_normalizeKey(key)];
      if (value != null && value != 'null') return value;
    }
    return '';
  }

  String _normalizeKey(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  void _confirm() {
    final result = <String, String>{};
    for (var index = 0; index < _fieldLabels.length; index++) {
      result[_fieldLabels[index]] = _controllers[index].text.trim();
    }
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    if (_showCamera) return _buildCameraState();
    return Scaffold(
      backgroundColor: const Color(0xfff7f8fc),
      appBar: AppBar(
        title: const Text(
          'KhmerScan',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child:
            _selectedImage == null ? _buildEmptyState() : _buildImagePreview(),
      ),
    );
  }

  Widget _buildEmptyState() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 34, 24, 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 104,
              height: 104,
              decoration: BoxDecoration(
                color: const Color(0xff243b7a),
                borderRadius: BorderRadius.circular(30),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x30243b7a),
                    blurRadius: 24,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: const Icon(
                Icons.badge_outlined,
                color: Colors.white,
                size: 56,
              ),
            ),
            const SizedBox(height: 26),
            const Text(
              'KhmerScan',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                color: Color(0xff182650),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Capture your ID card clearly and securely',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Color(0xff667085)),
            ),
            const SizedBox(height: 42),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton.icon(
                onPressed: _isPicking ? null : _openCamera,
                icon: const Icon(Icons.document_scanner_outlined),
                label: Text(
                  _isPicking ? 'Opening camera...' : 'Scan ID card',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xff243b7a),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Text(_errorMessage!, textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCameraState() {
    final controller = _cameraController;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Take ID card photo'),
        foregroundColor: Colors.white,
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () async {
            final controller = _cameraController;
            _cameraController = null;
            if (mounted) Navigator.of(context).pop();
            await controller?.dispose();
          },
        ),
      ),
      body:
          controller == null
              ? Center(
                child:
                    _errorMessage == null
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.camera_alt_outlined,
                              color: Colors.white,
                              size: 48,
                            ),
                            const SizedBox(height: 16),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                              ),
                              child: Text(
                                _errorMessage!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                            const SizedBox(height: 16),
                            FilledButton(
                              onPressed: _isPicking ? null : _openCamera,
                              child: const Text('Try again'),
                            ),
                          ],
                        ),
              )
              : Stack(
                fit: StackFit.expand,
                children: [
                  Center(child: CameraPreview(controller)),
                  IgnorePointer(
                    child: Center(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 28),
                        height: 220,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white, width: 2),
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                  const Positioned(
                    top: 24,
                    left: 24,
                    right: 24,
                    child: Text(
                      'Fit the ID card inside the frame',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 32,
                    left: 0,
                    right: 0,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton.filledTonal(
                          onPressed: _isPicking ? null : _openGallery,
                          icon: const Icon(Icons.photo_library_outlined),
                          tooltip: 'Upload image',
                          iconSize: 28,
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xff243b7a),
                            padding: const EdgeInsets.all(14),
                          ),
                        ),
                        const SizedBox(width: 34),
                        GestureDetector(
                          onTap: _takePhoto,
                          child: Container(
                            width: 78,
                            height: 78,
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 4),
                            ),
                            child: Container(
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
    );
  }

  Widget _buildImagePreview() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Review ID card details',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 8),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Adjust the crop, then type or review the card details below.',
              style: TextStyle(color: Color(0xff667085)),
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.file(_selectedImage!, fit: BoxFit.contain),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton.icon(
              onPressed: _isPicking ? null : _editCrop,
              icon: const Icon(Icons.crop),
              label: Text(_isPicking ? 'Opening crop editor...' : 'Edit crop'),
            ),
          ),
          if (_hasCroppedImage) ...[
            const SizedBox(height: 20),
            _buildDetailsForm(),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton.icon(
                onPressed:
                    _isPicking || _selectedImage == null
                        ? null
                        : () => _runOcr(_selectedImage!),
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Read text automatically'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: _confirm,
                icon: const Icon(Icons.check),
                label: const Text('Save details'),
              ),
            ),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton.icon(
              onPressed: _isPicking ? null : _openCamera,
              icon: const Icon(Icons.camera_alt_outlined),
              label: const Text('Take another photo'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Card information',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        ...List.generate(
          _fieldLabels.length,
          (index) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextField(
              controller: _controllers[index],
              textInputAction:
                  index == _fieldLabels.length - 1
                      ? TextInputAction.done
                      : TextInputAction.next,
              decoration: InputDecoration(
                labelText: _fieldLabels[index],
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
