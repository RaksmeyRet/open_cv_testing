import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/khemra_scanner_controller.dart';
import '../screens/photo_library_screen.dart';
import '../widgets/scanner_frame.dart';
import '../widgets/scanner_instruction.dart';
import '../widgets/scanner_overlay.dart';
import '../utils/scanner_utils.dart';

// ===========================================================================
// Main scanner screen
// ===========================================================================

class KhemraScannerScreen extends StatelessWidget {
  const KhemraScannerScreen({
    this.primaryColor = const Color(0xFF092469),
    this.secondaryColor = const Color(0xFFCF951B),
    super.key,
  });

  final Color primaryColor;
  final Color secondaryColor;

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(KhemraScannerController());
    return Obx(() {
      if (controller.showSampleGuide.value) {
        return _SampleGuideView(
          primaryColor: primaryColor,
          secondaryColor: secondaryColor,
        );
      }
      if (controller.showCamera.value) {
        return _CameraView(primaryColor: primaryColor);
      }
      return _PreviewFormView(primaryColor: primaryColor);
    });
  }
}

// ===========================================================================
// Sample guide screen (shown before camera opens)
// ===========================================================================

class _SampleGuideView extends GetView<KhemraScannerController> {
  const _SampleGuideView({
    required this.primaryColor,
    required this.secondaryColor,
  });

  final Color primaryColor;
  final Color secondaryColor;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final cardWidth = screenWidth * 0.47;
    final cardHeight = cardWidth * 1.22;
    final sampleInset = cardWidth * 0.075;
    final cardLeft = (screenWidth - cardWidth) / 2;
    final cardTop = (screenHeight - cardHeight) / 2 + screenHeight * 0.04;

    return Scaffold(
      backgroundColor: const Color(0xFF05070B),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Blurred background
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF181C23), Color(0xFF07090D)],
                ),
              ),
              child: Image.asset(
                'packages/id_scanner/assets/id_card.png',
                fit: BoxFit.cover,
                color: const Color(0x99000000),
                colorBlendMode: BlendMode.darken,
              ),
            ),
          ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: const SizedBox.expand(),
            ),
          ),
          // Header text
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 34, left: 24, right: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Sample ID card',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Use this sample as a guide when taking your ID card photo.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Card shadow frame
          Positioned(
            left: cardLeft - cardWidth * 0.09,
            top: cardTop - cardHeight * 0.06,
            child: Container(
              width: cardWidth * 1.18,
              height: cardHeight * 1.12,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                color: const Color(0x33000000),
                border: Border.all(color: const Color(0x55FFFFFF)),
              ),
            ),
          ),
          // Card with sample image
          Positioned(
            left: cardLeft,
            top: cardTop,
            child: Container(
              width: cardWidth,
              height: cardHeight,
              decoration: BoxDecoration(
                color: const Color(0xFFF4F5F7),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xFFDBDEE4), width: 1.2),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x3D000000),
                    blurRadius: 24,
                    offset: Offset(0, 18),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Padding(
                  padding: EdgeInsets.all(sampleInset),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFD3D7DC)),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(11),
                      child: RotatedBox(
                        quarterTurns: 1,
                        child: Image.asset(
                          'packages/id_scanner/assets/id_card.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Close button
          Positioned(
            left: cardLeft + cardWidth - 32,
            top: cardTop + cardHeight - 50,
            child: GestureDetector(
              onTap: controller.cancelSampleGuide,
              child: Container(
                width: 34,
                height: 34,
                decoration: const BoxDecoration(
                  color: Color(0xFFF7F7F7),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x44000000),
                      blurRadius: 8,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.close,
                  color: Color(0xFFE53935),
                  size: 21,
                ),
              ),
            ),
          ),
          // Bottom controls preview (decorative)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  height: 126,
                  padding: const EdgeInsets.only(bottom: 18),
                  decoration: const BoxDecoration(
                    color: Color(0xDD111418),
                    border: Border(top: BorderSide(color: Color(0x22FFFFFF))),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.photo_library_outlined,
                        color: Color(0x99FFFFFF),
                        size: 30,
                      ),
                      SizedBox(
                        width: 66,
                        height: 66,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Color(0xFFE8E8E8),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.flashlight_on_outlined,
                        color: Color(0x99FFFFFF),
                        size: 30,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Camera view
// ===========================================================================

class _CameraView extends GetView<KhemraScannerController> {
  const _CameraView({required this.primaryColor});

  final Color primaryColor;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Obx(() {
        final camera = controller.cameraCtrl.value;
        if (camera == null) return _buildCameraLoading();
        return _buildCameraReady(camera);
      }),
    );
  }

  Widget _buildCameraLoading() {
    final error = controller.errorMessage.value;
    if (error == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.camera_alt_outlined, color: Colors.white, size: 48),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
          ),
          const SizedBox(height: 16),
          Obx(
            () => FilledButton(
              onPressed:
                  controller.isPicking.value ? null : controller.openCamera,
              child: const Text('Try again'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraReady(CameraController camera) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isLandscape = constraints.maxWidth > constraints.maxHeight;
        final headerHeight = isLandscape ? 78.0 : 104.0;
        const controlsHeight = 118.0;
        const frameAspectRatio = 0.592;

        final cameraAreaHeight =
            constraints.maxHeight - headerHeight - controlsHeight;
        final maxFrameWidth =
            isLandscape
                ? constraints.maxWidth * 0.46
                : constraints.maxWidth * 0.78;
        final maxFrameHeight = maxFrameWidth / frameAspectRatio;
        const minimumFrameHeight = 160.0;
        final frameHeightLimit = math.max(
          1.0,
          math.min(maxFrameHeight, cameraAreaHeight),
        );
        final frameHeight = math.min(
          frameHeightLimit,
          math.max(
            math.min(minimumFrameHeight, frameHeightLimit),
            cameraAreaHeight * (isLandscape ? 0.78 : 0.62),
          ),
        );
        final frameWidth = frameHeight * frameAspectRatio;
        final frameRect = Rect.fromCenter(
          center: Offset(
            constraints.maxWidth / 2,
            headerHeight + cameraAreaHeight / 2,
          ),
          width: frameWidth,
          height: frameHeight,
        );

        return Stack(
          fit: StackFit.expand,
          children: [
            _CameraPreview(camera: camera),
            ScannerOverlay(frameRect: frameRect),
            Positioned.fromRect(rect: frameRect, child: const ScannerFrame()),
            SafeArea(
              child: Column(
                children: [
                  _CameraHeader(
                    primaryColor: primaryColor,
                    height: headerHeight,
                    isLandscape: isLandscape,
                  ),
                  const Spacer(),
                  _CameraControls(
                    camera: camera,
                    height: controlsHeight,
                    isLandscape: isLandscape,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CameraPreview extends StatelessWidget {
  const _CameraPreview({required this.camera});

  final CameraController camera;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AspectRatio(
        aspectRatio: 1 / camera.value.aspectRatio,
        child: CameraPreview(camera),
      ),
    );
  }
}

class _CameraHeader extends GetView<KhemraScannerController> {
  const _CameraHeader({
    required this.primaryColor,
    required this.height,
    required this.isLandscape,
  });

  final Color primaryColor;
  final double height;
  final bool isLandscape;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: EdgeInsets.fromLTRB(isLandscape ? 28 : 20, 8, 20, 8),
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
              onPressed: controller.closeAndPop,
              icon: Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Colors.white,
                size: isLandscape ? 22 : 26,
              ),
            ),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 50),
              child: Text(
                'សូមថតរូបអត្តសញ្ញាណប័ណ្ណ\nនៅផ្នែកខាងមុខ',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: isLandscape ? 14 : 15,
                  fontWeight: FontWeight.w600,
                  height: 2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraControls extends GetView<KhemraScannerController> {
  const _CameraControls({
    required this.camera,
    required this.height,
    required this.isLandscape,
  });

  final CameraController camera;
  final double height;
  final bool isLandscape;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isTorchOn = camera.value.flashMode == FlashMode.torch;
      final picking = controller.isPicking.value;

      return Container(
        height: height,
        padding: EdgeInsets.fromLTRB(
          isLandscape ? 64 : 40,
          isLandscape ? 8 : 14,
          isLandscape ? 64 : 40,
          isLandscape ? 10 : 16,
        ),
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
              labelOnLeft: true,
              buttonSize: 50,
              iconSize: 30,
              onPressed:
                  picking
                      ? null
                      : () => controller.openGallery(
                        () async =>
                            Get.to<File>(() => const PhotoLibraryScreen()),
                      ),
            ),
            Semantics(
              button: true,
              label: 'Capture ID card',
              child: IconButton(
                tooltip: 'Capture ID card',
                onPressed: picking ? null : controller.takePhoto,
                icon: SizedBox(
                  width: 78,
                  height: 78,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.fromBorderSide(
                        BorderSide(color: Colors.white, width: 2),
                      ),
                    ),
                    child: const Padding(
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
              icon:
                  isTorchOn
                      ? Icons.flash_on_rounded
                      : Icons.flashlight_on_rounded,
              label: 'ពិល',
              labelOnLeft: true,
              buttonSize: 50,
              iconSize: 30,
              active: isTorchOn,
              onPressed: picking ? null : controller.toggleFlash,
            ),
          ],
        ),
      );
    });
  }
}

// ===========================================================================
// Preview + form view (after image is captured/selected)
// ===========================================================================

class _PreviewFormView extends GetView<KhemraScannerController> {
  const _PreviewFormView({required this.primaryColor});

  final Color primaryColor;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: Obx(
          () => IconButton(
            tooltip: 'ត្រឡប់ទៅកាមេរ៉ា',
            onPressed:
                controller.isPicking.value ? null : controller.openCamera,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
        ),
        title: const Text(
          'ផ្ទៀងផ្ទាត់អត្តសញ្ញាណប័ណ្ណ',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Color(0xFF3F3F3F),
            overflow: TextOverflow.ellipsis,
            height: 2,
          ),
          textAlign: TextAlign.start,
          maxLines: 1,
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: const Color(0xFF092469),
      ),
      body: SafeArea(
        child: Obx(() {
          final image = controller.frontImage.value;
          if (image == null) {
            Get.back();
          }
          return _ImageAndForm(primaryColor: primaryColor);
        }),
      ),
    );
  }
}

class _ImageAndForm extends GetView<KhemraScannerController> {
  const _ImageAndForm({required this.primaryColor});

  final Color primaryColor;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ImagePreview(reloadAnimController: controller.reloadAnimController),
          const SizedBox(height: 20),
          Obx(() {
            final error = controller.errorMessage.value;
            if (error == null) return const SizedBox.shrink();
            return Column(
              children: [
                _OcrErrorBanner(message: error),
                const SizedBox(height: 20),
              ],
            );
          }),
          _DetailsForm(primaryColor: primaryColor),
          const SizedBox(height: 18),
          Obx(
            () => SizedBox(
              height: 56,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed:
                    controller.isFormValid && !controller.isPicking.value
                        ? controller.confirm
                        : null,
                child: const Text('បញ្ជូន', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImagePreview extends GetView<KhemraScannerController> {
  const _ImagePreview({required this.reloadAnimController});

  final AnimationController reloadAnimController;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.586,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Obx(() {
              final image = controller.frontImage.value;
              return image == null
                  ? const ColoredBox(color: Color(0xFFEAEAEA))
                  : Image.file(image, fit: BoxFit.cover);
            }),
            Obx(() {
              if (!controller.isPicking.value) return const SizedBox.shrink();
              return ColoredBox(
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
                        turns: reloadAnimController,
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
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _DetailsForm extends GetView<KhemraScannerController> {
  const _DetailsForm({required this.primaryColor});

  final Color primaryColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ព័ត៌មានអត្តសញ្ញាណ',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: primaryColor,
          ),
        ),
        const SizedBox(height: 8),
        const Divider(color: Color(0xFFEAEAEA), height: 1),
        const SizedBox(height: 16),
        _FormField(
          label: 'លេខអត្តសញ្ញាណ',
          hint: 'ID number',
          textController: controller.idNumberController,
          primaryColor: primaryColor,
          keyboardType: TextInputType.number,
          validate: (value) => ScannerUtils.fieldValidationError(0, value),
        ),
        _FormField(
          label: 'នាមត្រកូល',
          hint: 'Surname',
          textController: controller.surnameController,
          primaryColor: primaryColor,
          keyboardType: TextInputType.name,
          validate: (value) => ScannerUtils.fieldValidationError(1, value),
        ),
        _FormField(
          label: 'នាមខ្លួន',
          hint: 'Given name',
          textController: controller.usernameController,
          primaryColor: primaryColor,
          keyboardType: TextInputType.name,
          validate: (value) => ScannerUtils.fieldValidationError(2, value),
        ),
        _FormField(
          label: 'ថ្ងៃខែឆ្នាំកំណើត',
          hint: 'Date of birth',
          textController: controller.dateOfBirthController,
          primaryColor: primaryColor,
          keyboardType: TextInputType.datetime,
          validate: (value) => ScannerUtils.fieldValidationError(3, value),
        ),
        _FormField(
          label: 'ថ្ងៃផុតកំណត់',
          hint: 'Expiry date',
          textController: controller.expiryDateController,
          primaryColor: primaryColor,
          keyboardType: TextInputType.datetime,
          validate: (value) => ScannerUtils.fieldValidationError(4, value),
        ),
        _FormField(
          label: 'ភេទ',
          hint: 'Gender',
          textController: controller.genderController,
          primaryColor: primaryColor,
          keyboardType: TextInputType.name,
          validate: (value) => ScannerUtils.fieldValidationError(5, value),
        ),
        _FormField(
          label: 'ទីកន្លែងកំណើត',
          hint: 'Place of birth',
          textController: controller.placeOfBirthController,
          primaryColor: primaryColor,
          keyboardType: TextInputType.name,
          validate: (value) => ScannerUtils.fieldValidationError(6, value),
        ),
        _FormField(
          label: 'អាសយដ្ឋានបច្ចុប្បន្ន',
          hint: 'Address',
          textController: controller.addressController,
          primaryColor: primaryColor,
          keyboardType: TextInputType.name,
          isLast: true,
          validate: (value) => ScannerUtils.fieldValidationError(7, value),
        ),
      ],
    );
  }
}

class _FormField extends StatelessWidget {
  const _FormField({
    required this.label,
    required this.hint,
    required this.textController,
    required this.primaryColor,
    required this.validate,
    this.keyboardType = TextInputType.text,
    this.isLast = false,
  });

  final String label;
  final String hint;
  final TextEditingController textController;
  final Color primaryColor;
  final String? Function(String) validate;
  final TextInputType keyboardType;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: textController,
      builder: (context, value, _) {
        final text = value.text;
        final error = validate(text);
        final hasValue = text.trim().isNotEmpty;
        final isValid = !hasValue || error == null;
        final borderColor =
            isValid ? const Color(0xFFEAEAEA) : const Color(0xFFE53935);
        final baseBorder = OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: borderColor),
        );

        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6B7280),
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: textController,
                keyboardType: keyboardType,
                textInputAction:
                    isLast ? TextInputAction.done : TextInputAction.next,
                decoration: InputDecoration(
                  hintText: hint,
                  errorText: hasValue ? error : null,
                  errorMaxLines: 2,
                  suffixIcon:
                      hasValue
                          ? Icon(
                            isValid ? Icons.check_circle : Icons.error_outline,
                            color:
                                isValid
                                    ? const Color(0xFF00C300)
                                    : const Color(0xFFE53935),
                          )
                          : null,
                  enabledBorder: baseBorder,
                  focusedBorder: baseBorder.copyWith(
                    borderSide: BorderSide(color: primaryColor, width: 1.5),
                  ),
                  errorBorder: baseBorder.copyWith(
                    borderSide: const BorderSide(color: Color(0xFFE53935)),
                  ),
                  focusedErrorBorder: baseBorder.copyWith(
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
      },
    );
  }
}

class _OcrErrorBanner extends StatelessWidget {
  const _OcrErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
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
              message,
              style: const TextStyle(color: Color(0xFFE53935)),
            ),
          ),
        ],
      ),
    );
  }
}
