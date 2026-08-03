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
// crop_id_card
// ---------------------------------------------------------------------------
typedef CropIdCardC =
    Bool Function(
      Pointer<Uint8> inputPixels,
      Int32 width,
      Int32 height,
      Pointer<Uint8> outputPixels,
    );
typedef CropIdCardDart =
    bool Function(
      Pointer<Uint8> inputPixels,
      int width,
      int height,
      Pointer<Uint8> outputPixels,
    );

class NativeOpencv {
  static final DynamicLibrary _lib = _loadNativeLib();

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

  static final CropIdCardDart _cropIdCard =
      _lib.lookup<NativeFunction<CropIdCardC>>('crop_id_card').asFunction();

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
  /// Returns a tightly-packed RGBA buffer of size
  /// idCardOutputWidth * idCardOutputHeight * 4, or null if no card
  /// was detected.
  static Uint8List? cropIdCard(Uint8List rgbaBytes, int width, int height) {
    final outWidth = idCardOutputWidth;
    final outHeight = idCardOutputHeight;
    final outputLength = outWidth * outHeight * 4;

    final Pointer<Uint8> inputPointer = malloc<Uint8>(rgbaBytes.length);
    final Pointer<Uint8> outputPointer = malloc<Uint8>(outputLength);

    try {
      inputPointer.asTypedList(rgbaBytes.length).setAll(0, rgbaBytes);

      final bool success = _cropIdCard(
        inputPointer,
        width,
        height,
        outputPointer,
      );

      if (!success) {
        return null;
      }

      return Uint8List.fromList(outputPointer.asTypedList(outputLength));
    } finally {
      malloc.free(inputPointer);
      malloc.free(outputPointer);
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
