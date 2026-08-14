# native_opencv

A Flutter FFI plugin that wraps **OpenCV** for **Android** and **iOS**.  
It exposes real-time **blur detection** and **ID-card perspective-crop** via `dart:ffi` — no platform channels required, zero JNI overhead.

---

## Features

| Feature | Android | iOS |
|---|---|---|
| `getOpenCVVersion()` | ✅ | ✅ |
| `isImageBlurred()` | ✅ | ✅ |
| `cropIdCard()` | ✅ | ✅ |

---

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  native_opencv_kit: ^1.0.0
```

Then run:

```bash
flutter pub get
```

> **Note:** This plugin wraps the OpenCV native libraries.  
> You must supply the OpenCV SDK separately for each platform (see setup below).  
> The pre-built binaries are not bundled with the pub package due to their size (~2 GB).

---

## Android Setup

### 1. Download the OpenCV Android SDK

Download the **OpenCV Android SDK** from [opencv.org/releases/](https://opencv.org/releases/) (e.g. `opencv-4.10.0-android-sdk.zip`) and unzip it.

### 2. Copy SDK files into the plugin cache

After `flutter pub get`, the plugin will be downloaded to your Flutter pub cache.  
Navigate to it:

```
~/.pub-cache/hosted/pub.dev/native_opencv-<version>/android/
```

Copy these two folders from the unzipped OpenCV SDK into that `android/` directory:

```
android/
  sdk/
    native/
      jni/     ← CMake find-package configs and headers
      libs/    ← Pre-built .so files (arm64-v8a, armeabi-v7a, x86_64)
```

### 3. Verify `build.gradle`

The plugin's `android/build.gradle` is already configured to:
- Point CMake to `sdk/native/jni` for the OpenCV find-package path
- Bundle `sdk/native/libs/*.so` into your APK automatically

No additional Gradle changes are needed in your app.

### Minimum Android SDK

`minSdk = 31` (Android 12)

---

## iOS Setup

### 1. Download the OpenCV iOS Framework

Download **opencv2.framework** (or `opencv2.xcframework` for newer SDKs) from [opencv.org/releases/](https://opencv.org/releases/).

### 2. Copy the framework into the plugin cache

After `flutter pub get`, navigate to:

```
~/.pub-cache/hosted/pub.dev/native_opencv-<version>/ios/
```

Place the framework there:

```
ios/
  opencv2.framework/   ← copied from the OpenCV iOS SDK
```

### 3. CocoaPods

The plugin's `native_opencv.podspec` already declares the framework as a vendored dependency. Running `pod install` inside your app's `ios/` folder will pick it up automatically.

---

## Usage

```dart
import 'package:native_opencv_kit/native_opencv.dart';

// 1. Get the linked OpenCV version
final version = NativeOpencv.getOpenCVVersion();
print('OpenCV $version');

// 2. Blur detection
//    rgbaBytes — Uint8List from your camera frame (RGBA, width * height * 4 bytes)
final bool blurry = NativeOpencv.isImageBlurred(rgbaBytes, width, height);
if (blurry) {
  print('Image is too blurry, ask user to hold steady.');
}

// 3. ID-card cropping
//    Returns a new Uint8List (RGBA) of fixed size, or null when no card is found.
final int outW = NativeOpencv.idCardOutputWidth;
final int outH = NativeOpencv.idCardOutputHeight;

final Uint8List? cropped = NativeOpencv.cropIdCard(rgbaBytes, width, height);
if (cropped != null) {
  // Use cropped RGBA buffer (outW × outH × 4 bytes)
}
```

See the [`example/`](example/) folder for a full camera-based demo using `package:camera`.

---

## API Reference

### `NativeOpencv.getOpenCVVersion() → String`
Returns the OpenCV version string compiled into the native library (e.g. `"4.10.0"`).

### `NativeOpencv.isImageBlurred(Uint8List rgbaBytes, int width, int height) → bool`
Returns `true` when the Laplacian variance of the image falls below the blur threshold.  
Input must be a tightly-packed **RGBA** buffer (`width × height × 4` bytes).

### `NativeOpencv.idCardOutputWidth → int`
### `NativeOpencv.idCardOutputHeight → int`
Fixed output dimensions of the cropped ID-card image returned by `cropIdCard`.

### `NativeOpencv.cropIdCard(Uint8List rgbaBytes, int width, int height) → Uint8List?`
Detects a rectangular card in the frame, applies a perspective transform, and returns a normalised **RGBA** image of size `idCardOutputWidth × idCardOutputHeight × 4` bytes.  
Returns `null` when no card is detected.

---

## Native source

All C++ source lives in [`src/`](src/):

| File | Purpose |
|---|---|
| `native_opencv.cpp` | C FFI entry-points exported to Dart |
| `BlurDetector.cpp/.hpp` | Laplacian-variance blur metric |
| `IdCardCropper.cpp/.hpp` | Contour detection + perspective warp |
| `CMakeLists.txt` | CMake build (links OpenCV + `c++_shared`) |

---

## Contributing

Pull requests are welcome! Please open an issue first to discuss what you would like to change.

---

## License

MIT — see [LICENSE](LICENSE).
