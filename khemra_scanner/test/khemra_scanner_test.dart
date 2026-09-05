import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image_lib;
import 'package:khemra_scanner/khemra_scanner.dart';

void main() {
  test('result stores image path and validity', () {
    const result = KhemraScannerResult(imagePath: '/tmp/id.png', isValid: true);

    expect(result.imagePath, '/tmp/id.png');
    expect(result.isValid, isTrue);
  });

  test('processor rejects an undecodable capture', () async {
    final capture = XFile.fromData(Uint8List.fromList([1, 2, 3]));

    final result = await const ScannerProcessor().process(capture);

    expect(result.isValid, isFalse);
    expect(result.imagePath, isNull);
  });

  test('processor delegates decoded pixels to its validator', () async {
    final source = image_lib.Image(width: 2, height: 2);
    final png = image_lib.encodePng(source);
    var called = false;
    final processor = ScannerProcessor(
      validator: (rgba, width, height) {
        called = true;
        expect(rgba.length, 16);
        expect(width, 2);
        expect(height, 2);
        return false;
      },
    );

    final result = await processor.process(
      XFile.fromData(Uint8List.fromList(png), name: 'capture.png'),
    );

    expect(called, isTrue);
    expect(result.isValid, isFalse);
  });

  test('scanner exception contains a useful message', () {
    const error = KhemraScannerException('Camera permission was denied.');

    expect(error.toString(), contains('Camera permission was denied.'));
  });
}
