# khemra_scanner

A reusable Flutter camera scanner component. The package owns camera setup,
live capture, lifecycle, orientation correction, blur status, crop retry, and
result handling. Image processing is injected so an application can connect
OpenCV or another engine without exposing that engine through the scanner API.

```dart
final result = await KhemraScanner.scan(
	context,
	processor: ScannerProcessor(engine: MyOpenCvEngine()),
);
if (result.isValid) {
	debugPrint(result.imagePath);
}
```

An engine implements `ScannerEngine`. For this repository, the adapter can
delegate `isFrameBlurred` to `NativeOpencv.isImageBlurred` and `cropDocument`
to `NativeOpencv.cropIdCard`, returning the native crop dimensions in a
`ScannerProcessedImage`. The scanner package deliberately does not depend on a
local path or Git dependency, so it remains reusable and publishable.

The adapter can be created inline:

```dart
final engine = ScannerEngine(
	isFrameBlurred: NativeOpencv.isImageBlurred,
	cropDocument: (rgba, width, height) {
		final cropped = NativeOpencv.cropIdCard(rgba, width, height);
		if (cropped == null) return null;
		return ScannerProcessedImage(
			rgbaBytes: cropped,
			width: NativeOpencv.idCardOutputWidth,
			height: NativeOpencv.idCardOutputHeight,
		);
	},
);
```

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
