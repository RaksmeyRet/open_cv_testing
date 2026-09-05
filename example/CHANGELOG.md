## 1.0.1

* Add `CameraCaptureScreen` widget to `lib/camera_capture_screen.dart`.
  - Live camera stream with real-time blur detection
  - Manual capture button with ID-card perspective crop
  - Optional OCR via configurable `ocrBaseUrl`, `ocrPath`, and `ocrLanguage` params
  - Pops with cropped RGBA `Uint8List` on "Use This"
* Add `camera: ^0.11.0` and `http: ^1.2.0` as package dependencies.

## 1.0.0

* Initial public release.
* Blur detection via Laplacian variance (`isImageBlurred`).
* ID-card perspective crop (`cropIdCard`).
* Android (arm64-v8a, armeabi-v7a, x86_64) and iOS support.
* Pure FFI — no platform channels.
