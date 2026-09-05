import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:photo_manager/photo_manager.dart';

import '../image/image_cropper.dart';
import '../models/id_card_data.dart';
import '../models/khemra_scan_result.dart';
import '../ocr/ocr_service.dart';
import '../utils/scanner_utils.dart';
import '../widgets/scanner_frame.dart';
import '../widgets/scanner_instruction.dart';
import '../widgets/scanner_overlay.dart';

// ---------------------------------------------------------------------------
// Photo library screen (self-contained)
// ---------------------------------------------------------------------------

class _PhotoLibraryController extends GetxController {
  static const _pageSize = 60;

  final ScrollController scrollController = ScrollController();
  final photos = <AssetEntity>[].obs;
  final album = Rxn<AssetPathEntity>();
  final isLoading = true.obs;
  final hasMore = true.obs;
  final isPermissionDenied = false.obs;
  final isLimitedAccess = false.obs;
  final message = RxnString();
  final page = 0.obs;

  @override
  void onInit() {
    super.onInit();
    scrollController.addListener(_loadMoreWhenNeeded);
    _loadPhotoLibrary();
  }

  @override
  void onClose() {
    scrollController
      ..removeListener(_loadMoreWhenNeeded)
      ..dispose();
    super.onClose();
  }

  Future<void> _loadPhotoLibrary() async {
    final permission = await PhotoManager.requestPermissionExtend();
    if (!Get.context!.mounted) return;

    if (!permission.hasAccess) {
      isLoading.value = false;
      isPermissionDenied.value = true;
      message.value = 'Photo access is needed to select an ID card image.';
      return;
    }

    isPermissionDenied.value = false;
    isLimitedAccess.value = permission == PermissionState.limited;
    message.value = null;

    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      onlyAll: true,
    );
    if (albums.isEmpty) {
      isLoading.value = false;
      message.value = 'No photos were found on this device.';
      return;
    }

    album.value = albums.first;
    await _loadNextPage();
  }

  void _loadMoreWhenNeeded() {
    if (scrollController.position.extentAfter < 360) _loadNextPage();
  }

  Future<void> _loadNextPage() async {
    final currentAlbum = album.value;
    if (currentAlbum == null ||
        (isLoading.value && page.value > 0) ||
        !hasMore.value) {
      return;
    }

    isLoading.value = true;
    try {
      final nextPage = await currentAlbum.getAssetListPaged(
        page: page.value,
        size: _pageSize,
      );
      if (!Get.isRegistered<_PhotoLibraryController>()) return;
      photos.addAll(nextPage);
      page.value++;
      hasMore.value = nextPage.length == _pageSize;
      isLoading.value = false;
    } catch (_) {
      isLoading.value = false;
      message.value = 'Could not load your photos.';
    }
  }

  Future<void> selectPhoto(AssetEntity asset) async {
    final imageFile = await asset.file;
    if (imageFile == null) return;
    Get.back(result: imageFile);
  }

  Future<void> reload() async {
    photos.clear();
    page.value = 0;
    hasMore.value = true;
    isLoading.value = true;
    message.value = null;
    await _loadPhotoLibrary();
  }
}

class _PhotoLibraryScreen extends GetView<_PhotoLibraryController> {
  const _PhotoLibraryScreen();

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.put(_PhotoLibraryController());
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF092469),
        elevation: 0,
        title: const Text(
          'រូបថត',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          if (ctrl.isLimitedAccess.value)
            TextButton(
              onPressed: () async {
                await PhotoManager.presentLimited();
                await ctrl.reload();
              },
              child: const Text('Select more photos'),
            ),
        ],
      ),
      body: Obx(() {
        if (ctrl.message.value != null) {
          return _buildMessage(ctrl);
        }
        if (ctrl.photos.isEmpty && ctrl.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }
        return GridView.builder(
          controller: ctrl.scrollController,
          padding: const EdgeInsets.all(3),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 3,
            mainAxisSpacing: 3,
          ),
          itemCount:
              ctrl.photos.length + (ctrl.hasMore.value ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == ctrl.photos.length) {
              return const Center(child: CircularProgressIndicator());
            }
            return _PhotoTile(
              asset: ctrl.photos[index],
              onTap: () => ctrl.selectPhoto(ctrl.photos[index]),
            );
          },
        );
      }),
    );
  }

  Widget _buildMessage(_PhotoLibraryController ctrl) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.photo_library_outlined,
              size: 52,
              color: Color(0xFF6B7280),
            ),
            const SizedBox(height: 16),
            Text(ctrl.message.value!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: ctrl.reload,
              child: const Text('Allow access'),
            ),
            if (ctrl.isPermissionDenied.value) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: PhotoManager.openSetting,
                child: const Text('Open settings'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.asset, required this.onTap});

  final AssetEntity asset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: FutureBuilder<Uint8List?>(
        future: asset.thumbnailDataWithSize(const ThumbnailSize(360, 360)),
        builder: (context, snapshot) {
          final thumbnail = snapshot.data;
          if (thumbnail == null) {
            return const ColoredBox(color: Color(0xFFEAEAEA));
          }
          return Image.memory(thumbnail, fit: BoxFit.cover);
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Main KhemraScannerScreen
// ---------------------------------------------------------------------------

/// The main scanner screen widget.
///
/// Push this screen onto the navigator and await it to receive a
/// [KhemraScanResult] (or `null` if the user cancelled):
///
/// ```dart
/// final result = await Navigator.of(context).push<KhemraScanResult>(
///   MaterialPageRoute(builder: (_) => KhemraScannerScreen(
///     ocrBaseUrl: 'http://your-ocr-server:8212',
///   )),
/// );
/// ```
class KhemraScannerScreen extends StatefulWidget {
  const KhemraScannerScreen({
    required this.ocrBaseUrl,
    this.primaryColor = const Color(0xFF092469),
    this.secondaryColor = const Color(0xFFCF951B),
    super.key,
  });

  /// Base URL of the remote OCR server, e.g. `http://157.245.49.153:8212`.
  final String ocrBaseUrl;

  /// Primary brand colour. Defaults to the Khemra navy blue.
  final Color primaryColor;

  /// Accent colour. Defaults to the Khemra gold.
  final Color secondaryColor;

  @override
  State<KhemraScannerScreen> createState() => _KhemraScannerScreenState();
}

class _KhemraScannerScreenState extends State<KhemraScannerScreen>
    with SingleTickerProviderStateMixin {
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
  late final AnimationController _reloadController;

  late final OcrService _ocrService;

  static const List<String> _fieldLabels = IdCardData.defaultFieldLabels;
  static const List<String> _fieldLabelsKhmer =
      IdCardData.defaultFieldLabelsKhmer;

  @override
  void initState() {
    super.initState();
    _ocrService = OcrService(baseUrl: widget.ocrBaseUrl);
    _reloadController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
    for (final controller in _controllers) {
      controller.addListener(_updateFieldValidation);
    }
    _showCamera = true;
    _openCamera();
  }

  @override
  void dispose() {
    _reloadController.dispose();
    _cameraController?.dispose();
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _updateFieldValidation() {
    if (mounted) setState(() {});
  }

  // ---------------------------------------------------------------------------
  // Camera
  // ---------------------------------------------------------------------------

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
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _cameraController = controller);
    } catch (error) {
      if (mounted) {
        setState(() => _errorMessage = 'Camera could not be opened: $error');
      }
    } finally {
      _isOpeningCamera = false;
    }
  }

  Future<void> _takePhoto() async {
    final controller = _cameraController;
    if (controller == null ||
        !controller.value.isInitialized ||
        _isPicking) {
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
    if (controller == null ||
        !controller.value.isInitialized ||
        _isPicking) {
      return;
    }
    try {
      final nextMode = controller.value.flashMode == FlashMode.torch
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
      MaterialPageRoute(builder: (_) => const _PhotoLibraryScreen()),
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
      MaterialPageRoute(
        builder: (_) => KhemraImageCropperScreen(source: source),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // OCR
  // ---------------------------------------------------------------------------

  Future<void> _runOcr(File imageFile) async {
    setState(() {
      _isPicking = true;
      _errorMessage = null;
    });

    final result = await _ocrService.recognize(imageFile);

    if (!mounted) return;

    if (!result.isSuccess) {
      setState(() {
        _errorMessage = result.error;
        _isPicking = false;
      });
      return;
    }

    setState(() {
      for (var i = 0; i < _controllers.length; i++) {
        _controllers[i].text = result.values[i];
      }
      _isPicking = false;
    });
  }

  // ---------------------------------------------------------------------------
  // Form / confirm
  // ---------------------------------------------------------------------------

  void _confirm() {
    if (!_isFormValid) return;
    final result = KhemraScanResult(
      idNumber: _controllers[0].text.trim(),
      name: _controllers[1].text.trim(),
      dateOfBirth: _controllers[2].text.trim(),
      expiryDate: _controllers[3].text.trim(),
      gender: _controllers[4].text.trim(),
    );
    Navigator.of(context).pop(result);
  }

  bool get _isFormValid => List.generate(
    _controllers.length,
    (i) =>
        ScannerUtils.fieldValidationError(i, _controllers[i].text) == null,
  ).every((v) => v);

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_showCamera) return _buildCameraState();
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'ត្រឡប់ទៅកាមេរ៉ា',
          onPressed: _isPicking ? null : _openCamera,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text(
          'ផ្ទៀងផ្ទាត់អត្តសញ្ញាណប័ណ្ណ',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: const Color(0xFF092469),
      ),
      body: SafeArea(
        child: _frontImage == null
            ? _buildEmptyState()
            : _buildImagePreview(),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Empty state (no image yet)
  // ---------------------------------------------------------------------------

  Widget _buildEmptyState() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white, Color(0xFFEAEAEA)],
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
                  color: widget.secondaryColor,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Secure ID verification',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: widget.primaryColor,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Scan your ID card',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: widget.primaryColor,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Capture your ID card in a clean and secure way.',
                style: TextStyle(
                  fontSize: 15,
                  color: Color(0xFF6B7280),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: const Color(0xFFEAEAEA)),
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
                        color: widget.primaryColor,
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
                    Text(
                      'Ready to scan',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: widget.primaryColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Place the ID card inside the frame and take a clear photo.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFF6B7280),
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
                          backgroundColor: widget.primaryColor,
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
                    color: const Color(0xFFE53935).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFE53935)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Camera state
  // ---------------------------------------------------------------------------

  Widget _buildCameraState() {
    final controller = _cameraController;
    return Scaffold(
      backgroundColor: Colors.black,
      body: controller == null
          ? Center(
              child: _errorMessage == null
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
                          padding: const EdgeInsets.symmetric(horizontal: 24),
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
                    ScannerOverlay(frameRect: frameRect),
                    Positioned.fromRect(
                      rect: frameRect,
                      child: const ScannerFrame(),
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
      height: 104,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      decoration: const BoxDecoration(
        color: Color(0xFF181A1B),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
      ),
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
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 50),
              child: Text(
                'សូមថតរូបអត្តសញ្ញាណប័ណ្ណ\nនៅផ្នែកខាងមុខ',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  height: 1.5,
                ),
              ),
            ),
          ),
          const Align(
            alignment: Alignment.centerRight,
            child: CircleAvatar(
              radius: 22,
              backgroundColor: Color(0xFFE4ECC7),
              child: Icon(
                Icons.badge_outlined,
                size: 25,
                color: Color(0xFF263323),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraControls(CameraController controller) {
    final isTorchOn = controller.value.flashMode == FlashMode.torch;
    return Container(
      height: 118,
      padding: const EdgeInsets.fromLTRB(40, 14, 40, 16),
      decoration: const BoxDecoration(
        color: Color(0xFF181A1B),
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ScannerToolButton(
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
                width: 78,
                height: 78,
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
          ScannerToolButton(
            icon: isTorchOn
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

  // ---------------------------------------------------------------------------
  // Image preview + form
  // ---------------------------------------------------------------------------

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
                      ? const ColoredBox(color: Color(0xFFEAEAEA))
                      : Image.file(_frontImage!, fit: BoxFit.cover),
                  if (_isPicking)
                    ColoredBox(
                      color: const Color(0x99000000),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 42,
                              height: 42,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 3,
                              ),
                            ),
                            const SizedBox(height: 12),
                            RotationTransition(
                              turns: _reloadController,
                              child: const Icon(
                                Icons.refresh_rounded,
                                color: Colors.white,
                                size: 30,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'កំពុងអានទិន្នន័យ...',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
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
          if (_errorMessage != null) ...[
            _buildOcrErrorMessage(),
            const SizedBox(height: 20),
          ],
          _buildDetailsForm(),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton(
              onPressed: _isFormValid && !_isPicking ? _confirm : null,
              style: FilledButton.styleFrom(
                backgroundColor: widget.primaryColor,
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

  Widget _buildOcrErrorMessage() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFE53935).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFE53935).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFE53935)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage!,
              style: const TextStyle(color: Color(0xFFE53935)),
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
        Text(
          'ព័ត៌មានអត្តសញ្ញាណ',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: widget.primaryColor,
          ),
        ),
        const SizedBox(height: 8),
        const Divider(color: Color(0xFFEAEAEA), height: 1),
        const SizedBox(height: 16),
        ...List.generate(_fieldLabels.length, (index) {
          final error = ScannerUtils.fieldValidationError(
            index,
            _controllers[index].text,
          );
          final hasValue = _controllers[index].text.trim().isNotEmpty;
          final isValid = !hasValue || error == null;
          final borderColor = isValid
              ? const Color(0xFFEAEAEA)
              : const Color(0xFFE53935);
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
                    color: Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _controllers[index],
                  textInputAction: index == _fieldLabels.length - 1
                      ? TextInputAction.done
                      : TextInputAction.next,
                  keyboardType: index == 0 || index == 2 || index == 3
                      ? TextInputType.text
                      : TextInputType.name,
                  decoration: InputDecoration(
                    hintText: _fieldLabels[index],
                    errorText: hasValue ? error : null,
                    errorMaxLines: 2,
                    suffixIcon: hasValue
                        ? Icon(
                            isValid
                                ? Icons.check_circle
                                : Icons.error_outline,
                            color: isValid
                                ? const Color(0xFF00C300)
                                : const Color(0xFFE53935),
                          )
                        : null,
                    enabledBorder: border,
                    focusedBorder: border.copyWith(
                      borderSide: BorderSide(
                        color: widget.primaryColor,
                        width: 1.5,
                      ),
                    ),
                    errorBorder: border.copyWith(
                      borderSide: const BorderSide(
                        color: Color(0xFFE53935),
                      ),
                    ),
                    focusedErrorBorder: border.copyWith(
                      borderSide: const BorderSide(
                        color: Color(0xFFE53935),
                        width: 1.5,
                      ),
                    ),
                    filled: true,
                    fillColor: Colors.white,
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
}
