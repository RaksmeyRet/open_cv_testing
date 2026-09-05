/// KhemraScanner — a Flutter package for Cambodian ID card scanning.
///
/// ## Quick start
///
/// ```dart
/// import 'package:khemra_scanner/khemra_scanner.dart';
///
/// final result = await Navigator.of(context).push<KhemraScanResult>(
///   MaterialPageRoute(
///     builder: (_) => KhemraScannerScreen(
///       ocrBaseUrl: 'http://your-ocr-server:8212',
///     ),
///   ),
/// );
/// if (result != null) {
///   print(result.idNumber);
/// }
/// ```
library khemra_scanner;

// Models
export 'src/models/khemra_scan_result.dart';
export 'src/models/id_card_data.dart';

// Screens
export 'src/screens/khemra_scanner_screen.dart';

// Camera
export 'src/camera/scanner_camera.dart';
export 'src/camera/camera_controller.dart';

// Detection
export 'src/detection/id_card_detector.dart';
export 'src/detection/document_detector.dart';

// Image
export 'src/image/image_processor.dart';
export 'src/image/image_cropper.dart';
export 'src/image/image_quality.dart';

// OCR
export 'src/ocr/ocr_service.dart';
export 'src/ocr/text_recognizer.dart';

// Widgets
export 'src/widgets/scanner_overlay.dart';
export 'src/widgets/scanner_frame.dart';
export 'src/widgets/scanner_instruction.dart';

// Utils
export 'src/utils/scanner_utils.dart';
