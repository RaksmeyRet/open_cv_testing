import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'core/colors/app_colors.dart';
import 'four_corner_crop_screen.dart';
import 'photo_library_screen.dart';
import 'scan_camera_widgets.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final List<TextEditingController> _controllers = List.generate(
    5,
    (_) => TextEditingController(),
  );

  File? _frontImage;
  bool _isPicking = false;
  bool _isOpeningCamera = false;
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

  static const List<String> _fieldLabelsKhmer = [
    'លេខអត្តសញ្ញាណ',
    'គោត្តនាមនិងនាម',
    'ថ្ងៃខែឆ្នាំកំណើត',
    'ថ្ងៃផុតកំណត់',
    'ភេទ',
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
    for (final controller in _controllers) {
      controller.addListener(_updateFieldValidation);
    }
    _showCamera = true;
    _openCamera();
  }

  void _updateFieldValidation() {
    if (mounted) setState(() {});
  }

  Future<void> _openCamera() async {
    if (_isOpeningCamera) return;
    _isOpeningCamera = true;

    try {
      final previousController = _cameraController;
      setState(() {
        _showCamera = true;
        _errorMessage = null;
        _cameraController = null;
      });
      await previousController?.dispose();

      final cameras = await availableCameras();
      if (cameras.isEmpty) throw Exception('No camera found on this phone.');
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
      setState(() => _cameraController = controller);
    } catch (error) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Camera could not be opened: $error';
        });
      }
    } finally {
      _isOpeningCamera = false;
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
      final capturedFile = File(photo.path);
      if (mounted) setState(() => _cameraController = null);
      await controller.dispose();
      if (!mounted) return;

      final croppedFile = await _cropImage(capturedFile);
      if (!mounted) return;
      if (croppedFile == null) {
        await _openCamera();
        return;
      }

      setState(() {
        _frontImage = croppedFile;
        _showCamera = false;
      });
      await _runOcr(croppedFile);
    } catch (error) {
      if (mounted) {
        setState(() => _errorMessage = 'Could not take photo: $error');
      }
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  Future<void> _toggleFlash() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized || _isPicking) {
      return;
    }

    try {
      final nextMode =
          controller.value.flashMode == FlashMode.torch
              ? FlashMode.off
              : FlashMode.torch;
      await controller.setFlashMode(nextMode);
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) {
        setState(() => _errorMessage = 'Flashlight is not available: $error');
      }
    }
  }

  Future<void> _openGallery() async {
    final navigator = Navigator.of(context);
    if (_showCamera) {
      final controller = _cameraController;
      _cameraController = null;
      if (mounted) setState(() => _showCamera = false);
      await controller?.dispose();
    }
    final imageFile = await navigator.push<File>(
      MaterialPageRoute(builder: (_) => const PhotoLibraryScreen()),
    );
    if (!mounted || imageFile == null) return;

    final croppedFile = await _cropImage(imageFile);
    if (!mounted) return;
    if (croppedFile == null) {
      await _openCamera();
      return;
    }

    setState(() {
      _frontImage = croppedFile;
      _errorMessage = null;
      _showCamera = false;
    });
    await _runOcr(croppedFile);
  }

  Future<File?> _cropImage(File source) {
    return Navigator.of(context).push<File>(
      MaterialPageRoute(builder: (_) => FourCornerCropScreen(source: source)),
    );
  }

  Future<bool> _runOcr(File imageFile) async {
    setState(() {
      _isPicking = true;
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
      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 45),
      );
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode != 200) {
        throw Exception('OCR failed (HTTP ${response.statusCode})');
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final fields = _extractOcrFields(decoded);
      if (fields.isEmpty) throw Exception('OCR response has no fields');
      _fillMissingMrzFields(fields, decoded);

      final mrzId = _findMrzId(decoded);
      if (mrzId != null) {
        fields['idnumber'] = mrzId;
      }

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
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
    return false;
  }

  Map<String, String> _extractOcrFields(Map<String, dynamic> response) {
    final fields = <String, String>{};

    void visit(dynamic value, [String prefix = '']) {
      if (value is Map) {
        value.forEach((key, child) {
          final name = _normalizeKey('$key');
          if (child is Map || child is List) {
            visit(child, name);
          } else if (child != null) {
            final text = '$child'.trim();
            if (text.isNotEmpty && text != 'null') {
              fields[name] = text;
              if (prefix.isNotEmpty) fields['$prefix$name'] = text;
            }
          }
        });
      } else if (value is List) {
        for (final child in value) {
          visit(child, prefix);
        }
      }
    }

    visit(response['fields'] ?? response);
    return fields;
  }

  void _fillMissingMrzFields(
    Map<String, String> fields,
    Map<String, dynamic> response,
  ) {
    final rawText =
        [
          response['raw_text'],
          response['rawText'],
          response['text'],
          response['ocr_text'],
        ].whereType<String>().join('\n').toUpperCase();
    if (rawText.isEmpty) return;

    final idMatch = RegExp(r'IDKHM([0-9]{9})[0-9]').firstMatch(rawText);
    if (_fieldValue(fields, 0).isEmpty && idMatch != null) {
      fields['idnumber'] = idMatch.group(1)!;
    }

    final dateMatch = RegExp(
      r'(?<![0-9])([0-9]{6})[0-9][MF]',
    ).firstMatch(rawText);
    if (_fieldValue(fields, 2).isEmpty && dateMatch != null) {
      fields['dateofbirth'] = _formatMrzDate(dateMatch.group(1)!);
    }
  }

  String? _findMrzId(dynamic value) {
    String? found;

    void visit(dynamic child) {
      if (found != null) return;
      if (child is String) {
        final normalized = child.toUpperCase().replaceAll(' ', '');
        final match = RegExp(
          r'IDKHM[^0-9O]{0,4}([0-9O]{9})[0-9O]',
        ).firstMatch(normalized);
        if (match != null) {
          found = match.group(1)!.replaceAll('O', '0');
        }
      } else if (child is Map) {
        for (final item in child.values) {
          visit(item);
          if (found != null) return;
        }
      } else if (child is List) {
        for (final item in child) {
          visit(item);
          if (found != null) return;
        }
      }
    }

    visit(value);
    return found;
  }

  String _formatMrzDate(String value) {
    final year = int.parse(value.substring(0, 2));
    final fullYear = year <= 50 ? 2000 + year : 1900 + year;
    return '$fullYear-${value.substring(2, 4)}-${value.substring(4, 6)}';
  }

  String _fieldValue(Map<String, String> fields, int index) {
    const keys = [
      ['idnumber', 'idno', 'identitynumber', 'documentnumber'],
      [
        'name',
        'fullname',
        'full_name',
        'fullnameen',
        'full_name_en',
        'englishname',
        'nameen',
      ],
      ['dateofbirth', 'dob', 'birthdate', 'birth', 'datebirth'],
      [
        'expirydate',
        'expiry',
        'expirationdate',
        'expiration',
        'dateofexpiry',
        'validuntil',
      ],
      ['gender', 'sex', 'genderidentity'],
    ];
    for (final key in keys[index]) {
      final value = fields[_normalizeKey(key)];
      if (value != null && value.trim().isNotEmpty && value != 'null') {
        return value.trim();
      }
    }
    return '';
  }

  String _normalizeKey(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  void _confirm() {
    if (!_isFormValid) return;
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
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'ផ្ទៀងផ្ទាត់អត្តសញ្ញាណប័ណ្ណ',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
      ),
      body: SafeArea(
        child: _frontImage == null ? _buildEmptyState() : _buildImagePreview(),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF7F9FF), Color(0xFFEFF3FF)],
        ),
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 28, 22, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Secure ID verification',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryDark,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Scan your ID card',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Capture your ID card in a clean and secure way.',
                style: TextStyle(
                  fontSize: 15,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: AppColors.border),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x140F172A),
                      blurRadius: 16,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.primary, AppColors.primaryDark],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(32),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x334E7BFF),
                            blurRadius: 20,
                            offset: Offset(0, 12),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.badge_outlined,
                        color: Colors.white,
                        size: 62,
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Ready to scan',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Place the ID card inside the frame and take a clear photo.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 58,
                      child: FilledButton.icon(
                        onPressed: _isPicking ? null : _openCamera,
                        icon: const Icon(Icons.camera_alt_outlined),
                        label: Text(
                          _isPicking ? 'Opening camera...' : 'Scan ID card',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.error),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCameraState() {
    final controller = _cameraController;
    return Scaffold(
      backgroundColor: Colors.black,
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
              : LayoutBuilder(
                builder: (context, constraints) {
                  final frameWidth = constraints.maxWidth * 0.82;
                  final frameHeight = frameWidth / 1.57;
                  final frameRect = Rect.fromCenter(
                    center: Offset(
                      constraints.maxWidth / 2,
                      constraints.maxHeight * 0.49,
                    ),
                    width: frameWidth,
                    height: frameHeight,
                  );
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildCameraPreview(controller),
                      CustomPaint(painter: _ScanMaskPainter(frameRect)),
                      Positioned.fromRect(
                        rect: frameRect,
                        child: _buildScanFrame(),
                      ),
                      SafeArea(
                        child: Column(
                          children: [
                            _buildCameraHeader(),
                            const Spacer(),
                            _buildCameraControls(controller),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
    );
  }

  Widget _buildCameraPreview(CameraController controller) {
    return Center(
      child: AspectRatio(
        aspectRatio: 1 / controller.value.aspectRatio,
        child: CameraPreview(controller),
      ),
    );
  }

  Widget _buildCameraHeader() {
    return Container(
      height: 144,
      padding: const EdgeInsets.fromLTRB(28, 12, 28, 12),
      decoration: const BoxDecoration(
        color: Color(0xFF181A1B),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
      ),
      child: SizedBox(
        child: Stack(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                tooltip: 'Back',
                onPressed: () async {
                  final current = _cameraController;
                  _cameraController = null;
                  if (mounted) Navigator.of(context).pop();
                  await current?.dispose();
                },
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 50),
                child: Text(
                  'សូមថតរូបអត្តសញ្ញាណប័ណ្ណ\nនៅផ្នែកខាងមុខ',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    height: 1.5,
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: _buildCapturedSideThumbnail(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCapturedSideThumbnail() {
    return const CircleAvatar(
      radius: 22,
      backgroundColor: Color(0xFFE4ECC7),
      child: Icon(Icons.badge_outlined, size: 25, color: Color(0xFF263323)),
    );
  }

  Widget _buildScanFrame() {
    return Stack(
      children: const [
        FrameCorner(top: 0, left: 0, horizontal: true),
        FrameCorner(top: 0, left: 0, horizontal: false),
        FrameCorner(top: 0, right: 0, horizontal: true),
        FrameCorner(top: 0, right: 0, horizontal: false),
        FrameCorner(bottom: 0, left: 0, horizontal: true),
        FrameCorner(bottom: 0, left: 0, horizontal: false),
        FrameCorner(bottom: 0, right: 0, horizontal: true),
        FrameCorner(bottom: 0, right: 0, horizontal: false),
      ],
    );
  }

  Widget _buildCameraControls(CameraController controller) {
    final isTorchOn = controller.value.flashMode == FlashMode.torch;
    return Container(
      height: 150,
      padding: const EdgeInsets.fromLTRB(48, 28, 48, 30),
      decoration: const BoxDecoration(
        color: Color(0xFF181A1B),
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CameraTool(
            icon: Icons.photo_library_outlined,
            label: 'រូបភាព',
            onPressed: _isPicking ? null : _openGallery,
          ),
          Semantics(
            button: true,
            label: 'Capture ID card',
            child: IconButton(
              tooltip: 'Capture ID card',
              onPressed: _isPicking ? null : _takePhoto,
              icon: const SizedBox(
                width: 104,
                height: 104,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.fromBorderSide(
                      BorderSide(color: Colors.white, width: 2),
                    ),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(6),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          CameraTool(
            icon:
                isTorchOn
                    ? Icons.flash_on_rounded
                    : Icons.flashlight_on_rounded,
            label: 'ពន្លឺ',
            active: isTorchOn,
            onPressed: _isPicking ? null : _toggleFlash,
          ),
        ],
      ),
    );
  }

  Widget _buildImagePreview() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [ 
          AspectRatio(
            aspectRatio: 1.586,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _frontImage == null
                      ? const ColoredBox(color: AppColors.card)
                      : Image.file(_frontImage!, fit: BoxFit.cover),
                  if (_isPicking)
                    const ColoredBox(
                      color: Color(0x99000000),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 42,
                              height: 42,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 3,
                              ),
                            ),
                            SizedBox(height: 12),
                            Icon(
                              Icons.refresh_rounded,
                              color: Colors.white,
                              size: 28,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          _buildDetailsForm(),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton(
              onPressed: _isFormValid && !_isPicking ? _confirm : null,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1D3B74),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'បញ្ជូន',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
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
          'ព័ត៌មានអត្តសញ្ញាណ',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        const Divider(color: AppColors.border, height: 1),
        const SizedBox(height: 16),
        ...List.generate(_fieldLabels.length, (index) {
          final error = _validationError(index, _controllers[index].text);
          final hasValue = _controllers[index].text.trim().isNotEmpty;
          final isValid = !hasValue || error == null;
          final borderColor = isValid ? AppColors.border : AppColors.error;
          final border = OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: borderColor),
          );
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _fieldLabelsKhmer[index],
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _controllers[index],
                  textInputAction:
                      index == _fieldLabels.length - 1
                          ? TextInputAction.done
                          : TextInputAction.next,
                  keyboardType:
                      index == 0 || index == 2 || index == 3
                          ? TextInputType.text
                          : TextInputType.name,
                  decoration: InputDecoration(
                    hintText: _fieldLabels[index],
                    errorText: hasValue ? error : null,
                    errorMaxLines: 2,
                    suffixIcon:
                        hasValue
                            ? Icon(
                              isValid
                                  ? Icons.check_circle
                                  : Icons.error_outline,
                              color:
                                  isValid ? AppColors.success : AppColors.error,
                            )
                            : null,
                    enabledBorder: border,
                    focusedBorder: border.copyWith(
                      borderSide: const BorderSide(
                        color: AppColors.primary,
                        width: 1.5,
                      ),
                    ),
                    errorBorder: border.copyWith(
                      borderSide: const BorderSide(color: AppColors.error),
                    ),
                    focusedErrorBorder: border.copyWith(
                      borderSide: const BorderSide(
                        color: AppColors.error,
                        width: 1.5,
                      ),
                    ),
                    filled: true,
                    fillColor: AppColors.background,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  bool get _isFormValid => List.generate(
    _controllers.length,
    (index) => _validationError(index, _controllers[index].text) == null,
  ).every((isValid) => isValid);

  String? _validationError(int index, String value) {
    final text = value.trim();
    switch (index) {
      case 0:
        return RegExp(r'^\d{9}$').hasMatch(text)
            ? null
            : 'Enter the 9-digit ID number.';
      case 1:
        return text.length >= 2 && RegExp(r'[^\d]').hasMatch(text)
            ? null
            : 'Enter the card holder name.';
      case 2:
      case 3:
        return _isValidDate(text)
            ? null
            : 'Enter a valid date in YYYY-MM-DD format.';
      case 4:
        return const {'male', 'female', 'm', 'f'}.contains(text.toLowerCase())
            ? null
            : 'Enter Male, Female, M, or F.';
      default:
        return null;
    }
  }

  bool _isValidDate(String value) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (match == null) return false;
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    if (month < 1 || month > 12 || day < 1) return false;
    final parsed = DateTime(year, month, day);
    return parsed.year == year && parsed.month == month && parsed.day == day;
  }
}

/// Darkens everything outside the scan frame instead of dimming the whole preview.
class _ScanMaskPainter extends CustomPainter {
  _ScanMaskPainter(this.frameRect);

  final Rect frameRect;

  @override
  void paint(Canvas canvas, Size size) {
    final path =
        Path()
          ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
          ..addRect(frameRect)
          ..fillType = PathFillType.evenOdd;
    canvas.drawPath(
      path,
      Paint()..color = Colors.black.withValues(alpha: 0.45),
    );
  }

  @override
  bool shouldRepaint(_ScanMaskPainter oldDelegate) =>
      oldDelegate.frameRect != frameRect;
}
