# khemra_scanner

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
