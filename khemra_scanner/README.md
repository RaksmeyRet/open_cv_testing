# khemra_scanner

<<<<<<< HEAD
<<<<<<< HEAD
=======
>>>>>>> a675689 (finished created component)
A Flutter package for scanning Cambodian national ID cards with camera, OpenCV-powered cropping, and remote OCR.

## Features

- 📷 **Camera scanner** — live viewfinder with scan frame overlay  
- ✂️ **Four-corner crop** — drag corners to perspective-correct the captured image  
- 🔍 **OCR integration** — sends the cropped image to a remote server and parses the result  
- 🖼️ **Photo library picker** — choose an existing photo instead of using the camera  
- ✅ **Validation form** — editable text fields with inline validation for each ID card field  

## Getting started

Add the dependency to your `pubspec.yaml`:

```yaml
dependencies:
  khemra_scanner:
    path: ../khemra_scanner   # adjust path as needed
```

## Usage

```dart
import 'package:khemra_scanner/khemra_scanner.dart';

// Push the scanner screen and await the result
final result = await Navigator.of(context).push<KhemraScanResult>(
  MaterialPageRoute(
    builder: (_) => KhemraScannerScreen(
      ocrBaseUrl: 'http://your-ocr-server:8212',
    ),
  ),
);

if (result != null) {
  print(result.idNumber);    // 9-digit ID number
  print(result.name);        // Full name
  print(result.dateOfBirth); // YYYY-MM-DD
  print(result.expiryDate);  // YYYY-MM-DD
  print(result.gender);      // Male / Female / M / F
}
```

## Package structure

```
lib/
├── khemra_scanner.dart          ← barrel export
└── src/
    ├── camera/
    │   ├── scanner_camera.dart      ← ScannerCameraPreview widget
    │   └── camera_controller.dart  ← GetX camera lifecycle controller
    ├── detection/
    │   ├── id_card_detector.dart    ← OpenCV ID-card corner/crop API
    │   └── document_detector.dart  ← Generic document detection helpers
    ├── image/
    │   ├── image_processor.dart    ← YUV420/BGRA → RGBA + rotation
    │   ├── image_cropper.dart      ← Four-corner crop screen
    │   └── image_quality.dart      ← Blur detection wrapper
    ├── ocr/
    │   ├── ocr_service.dart        ← HTTP OCR client
    │   └── text_recognizer.dart    ← OCR response parser
    ├── models/
    │   ├── khemra_scan_result.dart ← Result data class
    │   └── id_card_data.dart       ← Field label constants
    ├── screens/
    │   └── khemra_scanner_screen.dart ← Main scanner screen
    ├── widgets/
    │   ├── scanner_overlay.dart    ← Dimmed surround painter
    │   ├── scanner_frame.dart      ← Corner-bracket frame widget
    │   └── scanner_instruction.dart ← Status + tool-button widgets
    └── utils/
        └── scanner_utils.dart      ← Validation & text helpers
```

## Requirements

- Flutter ≥ 1.17.0  
- Dart ≥ 3.10.4  
- `native_opencv_kit` (path dependency — included in parent project)  
- Camera, photo-library, and (optionally) internet permissions configured in your Android/iOS project  

## License

MIT
<<<<<<< HEAD
=======
A reusable Flutter camera scanner component. The package owns camera setup,
capture, lifecycle, and result handling. Image validation is injected so an
application can connect its preferred processing engine without exposing that
engine through the scanner API.

```dart
final result = await KhemraScanner.scan(context);
if (result.isValid) {
	debugPrint(result.imagePath);
}
```

To reuse the existing OpenCV plugin, pass a `ScannerProcessor` whose validator
calls `NativeOpencv.isImageBlurred` and performs any application-specific card
validation. The scanner package deliberately does not depend on a local path
or Git dependency, so it remains publishable.

Camera permission is requested by the `camera` plugin during initialization.
The consuming Android application must declare `android.permission.CAMERA` in
its manifest; iOS applications must provide `NSCameraUsageDescription` in
`Info.plist`.
<!--
This README describes the package. If you publish this package to pub.dev,
this README's contents appear on the landing page for your package.

For information about how to write a good package README, see the guide for
[writing package pages](https://dart.dev/tools/pub/writing-package-pages).

For general information about developing packages, see the Dart guide for
[creating packages](https://dart.dev/guides/libraries/create-packages)
and the Flutter guide for
[developing packages and plugins](https://flutter.dev/to/develop-packages).
-->

TODO: Put a short description of the package here that helps potential users
know whether this package might be useful for them.

## Features

TODO: List what your package can do. Maybe include images, gifs, or videos.

## Getting started

TODO: List prerequisites and provide or point to information on how to
start using the package.

## Usage

TODO: Include short and useful examples for package users. Add longer examples
to `/example` folder.

```dart
const like = 'sample';
```

## Additional information

TODO: Tell users more about the package: where to find more information, how to
contribute to the package, how to file issues, what response they can expect
from the package authors, and more.
>>>>>>> 30a05c6 (add)
=======
>>>>>>> a675689 (finished created component)
