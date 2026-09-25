# id_scanner

A reusable Flutter package for scanning Cambodian national ID cards.

## Features

- 📷 **Camera scanner** — full-screen camera view with a guiding frame overlay
- 🔍 **OpenCV corner detection** — automatic ID card edge & corner detection via native FFI
- ✂️ **Perspective crop** — interactive four-corner crop screen with auto-detect
- 📖 **Multi-engine OCR** — Google ML Kit + Tesseract OCR (Khmer + English)
- 🇰🇭 **Cambodian ID card support** — MRZ parsing, Khmer field extraction
- 🎨 **Customizable colours** — primary and secondary brand colours

## Getting started

Add the package to your `pubspec.yaml`:

```yaml
dependencies:
  id_scanner:
    path: ../id_scanner   # or your local/pub path
```

### Android

Minimum SDK: **31** (Android 12). The NDK version **28.2.13676358** is required to build the OpenCV native library.

In your app's `android/app/build.gradle.kts`:

```kotlin
android {
    compileSdk = 36
    ndkVersion = "28.2.13676358"

    defaultConfig {
        minSdk = 31
        targetSdk = 36
    }
}
```

Add the following permissions to `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />
<uses-permission android:name="android.permission.READ_MEDIA_VISUAL_USER_SELECTED" />
<uses-permission
    android:name="android.permission.READ_EXTERNAL_STORAGE"
    android:maxSdkVersion="32" />
```

Inside `<application>`:

```xml
<activity
    android:name="com.yalantis.ucrop.UCropActivity"
    android:screenOrientation="portrait"
    android:theme="@style/Ucrop.CropTheme" />
```

### Assets

The package bundles the Tesseract trained data for Khmer and English. Your consuming app's `pubspec.yaml` must include the package assets:

```yaml
flutter:
  assets:
    - packages/id_scanner/assets/id_card.png
    - packages/id_scanner/assets/tessdata_config.json
    - packages/id_scanner/assets/tessdata/
```

## Usage

```dart
import 'package:id_scanner/id_scanner.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const MaterialApp(home: MyHomePage()));
}

class MyHomePage extends StatelessWidget {
  const MyHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () => _startScan(context),
          child: const Text('Scan ID Card'),
        ),
      ),
    );
  }

  Future<void> _startScan(BuildContext context) async {
    final result = await Navigator.of(context).push<KhemraScanResult>(
      MaterialPageRoute(
        builder: (_) => const KhemraScannerScreen(
          primaryColor: Color(0xFF092469),   // optional – default Khemra blue
          secondaryColor: Color(0xFFCF951B), // optional – default Khemra gold
        ),
      ),
    );

    if (result != null) {
      // result.idNumber, result.surname, result.username, etc.
      print(result);
    }
  }
}
```

## Public API

### `KhemraScannerScreen`

| Parameter | Type | Default | Description |
|---|---|---|---|
| `primaryColor` | `Color` | `Color(0xFF092469)` | Main brand/accent colour |
| `secondaryColor` | `Color` | `Color(0xFFCF951B)` | Secondary accent colour |

Pops with `KhemraScanResult` on confirm, `null` on cancel.

### `KhemraScanResult`

| Field | Type | Description |
|---|---|---|
| `idNumber` | `String?` | 9-digit Cambodian ID number |
| `surname` | `String?` | Family name (from MRZ) |
| `username` | `String?` | Given name (from MRZ) |
| `dateOfBirth` | `String?` | YYYY-MM-DD |
| `expiryDate` | `String?` | YYYY-MM-DD |
| `gender` | `String?` | `M` or `F` |
| `placeOfBirth` | `String?` | Khmer place of birth |
| `address` | `String?` | Khmer address |

### `ScannerUtils`

Utility methods for date validation, MRZ date formatting, and field-level validation.

### `KhemraImageCropperScreen`

Interactive four-corner crop screen. Used internally by `KhemraScannerScreen` but also exportable for custom flows.

### `OcrService`

Multi-engine OCR orchestrator (ML Kit + Tesseract + OpenCV preprocessing). Can be used independently for custom scanner UIs.

## License

MIT
