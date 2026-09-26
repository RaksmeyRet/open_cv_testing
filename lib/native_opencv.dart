import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:flutter/cupertino.dart';

// ---------------------------------------------------------------------------
// get_opencv_version
// ---------------------------------------------------------------------------
typedef GetVersionC = Pointer<Utf8> Function();
typedef GetVersionDart = Pointer<Utf8> Function();

// ---------------------------------------------------------------------------
// blur_check
// ---------------------------------------------------------------------------
typedef BlurCheckC =
    Bool Function(Pointer<Uint8> inputPixels, Int32 width, Int32 height);
typedef BlurCheckDart =
    bool Function(Pointer<Uint8> inputPixels, int width, int height);

// ---------------------------------------------------------------------------
// get_id_card_output_width / get_id_card_output_height
// ---------------------------------------------------------------------------
typedef GetIntC = Int32 Function();
typedef GetIntDart = int Function();

// ---------------------------------------------------------------------------
// detect_id_card_corners
// ---------------------------------------------------------------------------
typedef DetectCornersC =
    Bool Function(
      Pointer<Uint8> inputPixels,
      Int32 width,
      Int32 height,
      Pointer<Float> outCorners,
    );
typedef DetectCornersDart =
    bool Function(
      Pointer<Uint8> inputPixels,
      int width,
      int height,
      Pointer<Float> outCorners,
    );

// ---------------------------------------------------------------------------
// crop_id_card
// ---------------------------------------------------------------------------
typedef CropIdCardC =
    Bool Function(
      Pointer<Uint8> inputPixels,
      Int32 width,
      Int32 height,
      Pointer<Uint8> outPixels,
    );
typedef CropIdCardDart =
    bool Function(
      Pointer<Uint8> inputPixels,
      int width,
      int height,
      Pointer<Uint8> outPixels,
    );

// ---------------------------------------------------------------------------
// get_ocr_output_height
// ---------------------------------------------------------------------------
typedef GetOcrOutputHeightC = Int32 Function(Int32 width, Int32 height);
typedef GetOcrOutputHeightDart = int Function(int width, int height);

// ---------------------------------------------------------------------------
// preprocess_ocr_image
// ---------------------------------------------------------------------------
typedef PreprocessOcrImageC =
    Bool Function(
      Pointer<Uint8> inputPixels,
      Int32 width,
      Int32 height,
      Pointer<Uint8> outPixels,
    );
typedef PreprocessOcrImageDart =
    bool Function(
      Pointer<Uint8> inputPixels,
      int width,
      int height,
      Pointer<Uint8> outPixels,
    );

// ---------------------------------------------------------------------------
// extract_khmer_locations
// ---------------------------------------------------------------------------
typedef ExtractKhmerLocationsC =
    Bool Function(
      Pointer<Utf8> inputText,
      Pointer<Uint8> outPlaceOfBirth,
      Int32 placeBufferSize,
      Pointer<Uint8> outAddress,
      Int32 addressBufferSize,
    );
typedef ExtractKhmerLocationsDart =
    bool Function(
      Pointer<Utf8> inputText,
      Pointer<Uint8> outPlaceOfBirth,
      int placeBufferSize,
      Pointer<Uint8> outAddress,
      int addressBufferSize,
    );

class NativeOpencv {
  static final DynamicLibrary _lib = _loadNativeLib();

  static const int _ocrOutputWidth = 2000;
  static const int _khmerLocationBufferSize = 512;

  static final GetVersionDart _getVersion =
      _lib
          .lookup<NativeFunction<GetVersionC>>('get_opencv_version')
          .asFunction();

  static final BlurCheckDart _blurCheck =
      _lib.lookup<NativeFunction<BlurCheckC>>('blur_check').asFunction();

  static final GetIntDart _getIdCardOutputWidth =
      _lib
          .lookup<NativeFunction<GetIntC>>('get_id_card_output_width')
          .asFunction();

  static final GetIntDart _getIdCardOutputHeight =
      _lib
          .lookup<NativeFunction<GetIntC>>('get_id_card_output_height')
          .asFunction();

  static final DetectCornersDart _detectCorners =
      _lib
          .lookup<NativeFunction<DetectCornersC>>('detect_id_card_corners')
          .asFunction();

  static final CropIdCardDart _cropIdCard =
      _lib
          .lookup<NativeFunction<CropIdCardC>>('crop_id_card')
          .asFunction();

  static final GetOcrOutputHeightDart _getOcrOutputHeight =
      _lib
          .lookup<NativeFunction<GetOcrOutputHeightC>>(
            'get_ocr_output_height',
          )
          .asFunction();

  static final PreprocessOcrImageDart _preprocessOcrImage =
      _lib
          .lookup<NativeFunction<PreprocessOcrImageC>>(
            'preprocess_ocr_image',
          )
          .asFunction();

  static final ExtractKhmerLocationsDart _extractKhmerLocations =
      _lib
          .lookup<NativeFunction<ExtractKhmerLocationsC>>(
            'extract_khmer_locations',
          )
          .asFunction();

  // -------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------

  static String getOpenCVVersion() {
    final pointer = _getVersion();
    return pointer.toDartString();
  }

  /// [rgbaBytes] must be a tightly-packed RGBA buffer
  /// (width * height * 4 bytes). Returns true if the image is blurry.
  static bool isImageBlurred(Uint8List rgbaBytes, int width, int height) {
    final Pointer<Uint8> inputPointer = malloc<Uint8>(rgbaBytes.length);

    try {
      inputPointer.asTypedList(rgbaBytes.length).setAll(0, rgbaBytes);
      return _blurCheck(inputPointer, width, height);
    } finally {
      malloc.free(inputPointer);
    }
  }

  static int get idCardOutputWidth => _getIdCardOutputWidth();
  static int get idCardOutputHeight => _getIdCardOutputHeight();

  /// [rgbaBytes] is the source frame's RGBA buffer (any width/height).
  /// Returns the 4 detected card corners in pixel coordinates, ordered
  /// TL, TR, BR, BL, or null if no card was detected.
  static List<Offset>? detectIdCardCorners(
    Uint8List rgbaBytes,
    int width,
    int height,
  ) {
    final Pointer<Uint8> inputPointer = malloc<Uint8>(rgbaBytes.length);
    final Pointer<Float> cornersPointer = malloc<Float>(8);

    try {
      inputPointer.asTypedList(rgbaBytes.length).setAll(0, rgbaBytes);

      final bool success = _detectCorners(
        inputPointer,
        width,
        height,
        cornersPointer,
      );

      if (!success) {
        return null;
      }

      final values = cornersPointer.asTypedList(8);
      return List<Offset>.generate(
        4,
        (i) => Offset(values[i * 2], values[i * 2 + 1]),
      );
    } finally {
      malloc.free(inputPointer);
      malloc.free(cornersPointer);
    }
  }

  /// Perspective-crops and deskews the ID card in [rgbaBytes] to a
  /// standard [idCardOutputWidth] × [idCardOutputHeight] RGBA image.
  /// Returns null if no card was detected.
  static Uint8List? cropIdCard(Uint8List rgbaBytes, int width, int height) {
    final Pointer<Uint8> inputPointer = malloc<Uint8>(rgbaBytes.length);
    final int outLength = idCardOutputWidth * idCardOutputHeight * 4;
    final Pointer<Uint8> outputPointer = malloc<Uint8>(outLength);

    try {
      inputPointer.asTypedList(rgbaBytes.length).setAll(0, rgbaBytes);

      final bool success = _cropIdCard(
        inputPointer,
        width,
        height,
        outputPointer,
      );

      if (!success) return null;

      return Uint8List.fromList(outputPointer.asTypedList(outLength));
    } finally {
      malloc.free(inputPointer);
      malloc.free(outputPointer);
    }
  }

  /// The height a preprocessed OCR image will have once scaled to the
  /// fixed output width, preserving the aspect ratio of [width] × [height].
  static int getOcrOutputHeight(int width, int height) {
    return _getOcrOutputHeight(width, height);
  }

  /// Preprocesses [rgbaBytes] (deskew/binarize/etc.) for OCR, scaling it to
  /// a fixed output width with a proportional height (see
  /// [getOcrOutputHeight]). Returns a flat single-channel (grayscale)
  /// buffer of size `outputWidth * outputHeight`, or null on failure.
  static Uint8List? preprocessOcrImage(
    Uint8List rgbaBytes,
    int width,
    int height,
  ) {
    final int outputHeight = getOcrOutputHeight(width, height);
    final int outLength = _ocrOutputWidth * outputHeight;

    final Pointer<Uint8> inputPointer = malloc<Uint8>(rgbaBytes.length);
    final Pointer<Uint8> outputPointer = malloc<Uint8>(outLength);

    try {
      inputPointer.asTypedList(rgbaBytes.length).setAll(0, rgbaBytes);

      final bool success = _preprocessOcrImage(
        inputPointer,
        width,
        height,
        outputPointer,
      );

      if (!success) return null;

      return Uint8List.fromList(outputPointer.asTypedList(outLength));
    } finally {
      malloc.free(inputPointer);
      malloc.free(outputPointer);
    }
  }

  /// Extracts Khmer place-of-birth and address locations from [text].
  /// Returns a map with keys `place_of_birth` and `address`, or null if
  /// nothing was found.
  static Map<String, String>? extractKhmerLocations(String text) {
    final Pointer<Utf8> inputPointer = text.toNativeUtf8();
    final Pointer<Uint8> placePointer = malloc<Uint8>(
      _khmerLocationBufferSize,
    );
    final Pointer<Uint8> addressPointer = malloc<Uint8>(
      _khmerLocationBufferSize,
    );

    try {
      final bool success = _extractKhmerLocations(
        inputPointer,
        placePointer,
        _khmerLocationBufferSize,
        addressPointer,
        _khmerLocationBufferSize,
      );

      if (!success) return null;

      return {
        'place_of_birth': placePointer.cast<Utf8>().toDartString(),
        'address': addressPointer.cast<Utf8>().toDartString(),
      };
    } finally {
      malloc.free(inputPointer);
      malloc.free(placePointer);
      malloc.free(addressPointer);
    }
  }
}

DynamicLibrary _loadNativeLib() {
  if (Platform.isAndroid) {
    try {
      DynamicLibrary.open('libopencv_java4.so');
    } catch (e) {
      debugPrint('Could not load libopencv_java4.so directly: $e');
    }
    return DynamicLibrary.open('libnative_opencv.so');
  } else if (Platform.isIOS) {
    return DynamicLibrary.process();
  }
  throw UnsupportedError('Unsupported platform');
}