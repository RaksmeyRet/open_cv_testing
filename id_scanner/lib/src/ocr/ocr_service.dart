import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart'
    as mlkit;
import 'package:id_scanner/id_scanner.dart';
import 'package:image/image.dart' as img;
import 'package:native_opencv_kit/native_opencv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tesseract_ocr/ocr_engine_config.dart';
import 'package:tesseract_ocr/tesseract_ocr.dart';

class _OcrRawResult {
  const _OcrRawResult(this.values);
  final List<String> values;
}

class OcrService {
  OcrService();

  final _localRecognizer = mlkit.TextRecognizer(
    script: mlkit.TextRecognitionScript.latin,
  );

  static const int _fieldCount = 8;

  void dispose() {
    _localRecognizer.close();
  }

  Future<KhemraScanResult?> recognize(File imageFile) async {
    File? preparedFile;
    try {
      preparedFile = await _prepareWithCppPipeline(imageFile);
      final ocrImage = preparedFile ?? imageFile;
      final tesseractResult = await _recognizeWithTesseract(ocrImage);
      final originalTesseractResult =
          preparedFile == null
              ? null
              : await _recognizeWithTesseract(imageFile);
      final topZoneTesseractResult = await _recognizeTopZoneWithTesseract(
        imageFile,
      );
      final localResult = await _recognizeLocally(imageFile);
      final result = _mergeResults(
        _mergeResults(
          _mergeResults(tesseractResult, originalTesseractResult),
          topZoneTesseractResult,
        ),
        localResult,
      );
      
      if (result == null) return null;
      
      return KhemraScanResult(
        idNumber: result.values[0].isNotEmpty ? result.values[0] : null,
        surname: result.values[1].isNotEmpty ? result.values[1] : null,
        username: result.values[2].isNotEmpty ? result.values[2] : null,
        dateOfBirth: result.values[3].isNotEmpty ? result.values[3] : null,
        expiryDate: result.values[4].isNotEmpty ? result.values[4] : null,
        gender: result.values[5].isNotEmpty ? result.values[5] : null,
        placeOfBirth: result.values[6].isNotEmpty ? result.values[6] : null,
        address: result.values[7].isNotEmpty ? result.values[7] : null,
      );
    } catch (error) {
      throw Exception('OCR processing failed: $error');
    } finally {
      if (preparedFile != null) {
        try {
          await preparedFile.delete();
        } catch (_) {
          // Temporary OCR files are best-effort cleanup.
        }
      }
    }
  }

  _OcrRawResult? _mergeResults(
    _OcrRawResult? first,
    _OcrRawResult? second,
  ) {
    if (first == null && second == null) return null;
    final values = List<String>.filled(_fieldCount, '');
    for (var index = 0; index < values.length; index++) {
      final firstValue = first?.values[index].trim() ?? '';
      final secondValue = second?.values[index].trim() ?? '';
      values[index] = firstValue.isNotEmpty ? firstValue : secondValue;
    }
    return _OcrRawResult(values);
  }

  Future<File?> _prepareWithCppPipeline(File imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;
      final rgba = decoded.getBytes(order: img.ChannelOrder.rgba);
      final prepared = NativeOpencv.preprocessOcrImage(
        rgba,
        decoded.width,
        decoded.height,
      );
      if (prepared == null) return null;

      const width = 2000;
      final height = NativeOpencv.getOcrOutputHeight(
        decoded.width,
        decoded.height,
      );
      final preparedImage = img.Image(width: width, height: height);
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final value = prepared[y * width + x];
          preparedImage.setPixelRgba(x, y, value, value, value, 255);
        }
      }

      final directory = await getTemporaryDirectory();
      final preparedFile = File(
        '${directory.path}/cpp_ocr_${DateTime.now().microsecondsSinceEpoch}.png',
      );
      await preparedFile.writeAsBytes(img.encodePng(preparedImage));
      return preparedFile;
    } catch (_) {
      return null;
    }
  }

  Future<_OcrRawResult?> _recognizeWithTesseract(File imageFile) async {
    try {
      final text = await TesseractOcr.extractText(
        imageFile.path,
        config: OCRConfig(
          language: 'khm+eng',
          engine: OCREngine.tesseract,
          options: {
            TesseractConfig.pageSegMode: PageSegmentationMode.singleColumn,
            TesseractConfig.preserveInterwordSpaces: '1',
          },
        ),
      );
      return _resultFromText(text);
    } catch (_) {
      return null;
    }
  }

  Future<_OcrRawResult?> _recognizeLocally(File imageFile) async {
    try {
      final text = await _readTextAtUsefulScales(imageFile);
      return _resultFromText(text);
    } catch (_) {
      // Return a failed result when on-device OCR is unavailable.
    }
    return null;
  }

  Future<_OcrRawResult?> _recognizeTopZoneWithTesseract(
    File imageFile,
  ) async {
    File? topZoneFile;
    try {
      final bytes = await imageFile.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;

      final topZone = img.copyCrop(
        decoded,
        x: 0,
        y: 0,
        width: decoded.width,
        height: (decoded.height * 0.65).round(),
      );
      final enlarged = img.copyResize(
        topZone,
        width: topZone.width < 2000 ? 2000 : topZone.width,
      );
      final directory = await getTemporaryDirectory();
      topZoneFile = File(
        '${directory.path}/ocr_top_${DateTime.now().microsecondsSinceEpoch}.png',
      );
      await topZoneFile.writeAsBytes(img.encodePng(enlarged));
      return await _recognizeWithTesseract(topZoneFile);
    } catch (_) {
      return null;
    } finally {
      try {
        await topZoneFile?.delete();
      } catch (_) {
        // Temporary OCR files are best-effort cleanup.
      }
    }
  }

  _OcrRawResult? _resultFromText(String text) {
    try {
      final upperText = text.toUpperCase();
      final compact = upperText.replaceAll(RegExp(r'[^A-Z0-9<]'), '');
      final idMatch = RegExp(
        r'(?:IDKHM|LDKHM|TDKHM)([0-9O]{9})[0-9O]',
      ).firstMatch(compact);
      final personalMatch = RegExp(
        r'([0-9]{6})[0-9<]?([MF])([0-9]{6})[0-9<]?',
      ).firstMatch(compact);
      final nameMatch = _findMrzName(upperText);

      final values = List.filled(_fieldCount, '');
      if (idMatch != null) {
        values[0] = idMatch.group(1)!.replaceAll('O', '0');
      }
      if (nameMatch != null) {
        values[1] = nameMatch.group(1)!;
        values[2] = nameMatch.group(2)!;
      }
      if (personalMatch != null) {
        values[3] = _formatMrzDate(personalMatch.group(1)!);
        values[4] = _formatMrzDate(personalMatch.group(3)!, isExpiry: true);
        values[5] = personalMatch.group(2)!;
      }
      _extractPlaceAndAddress(text, values);
      final cppLocations = NativeOpencv.extractKhmerLocations(text);
      if (cppLocations != null) {
        final placeOfBirth = _cleanCppLocation(cppLocations['place_of_birth']!);
        final address = _cleanCppLocation(cppLocations['address']!);
        if (values[6].trim().isEmpty && placeOfBirth.isNotEmpty) {
          values[6] = placeOfBirth;
        }
        if (address.isNotEmpty) values[7] = address;
      }

      if (values.any((value) => value.isNotEmpty)) {
        return _OcrRawResult(values);
      }
    } catch (_) {
      // Ignore malformed OCR output and let the fallback recognizer run.
    }
    return null;
  }

  String _cleanCppLocation(String rawValue) {
    final withoutLabels = rawValue
        .replaceAll(
          RegExp(
            r'(?:ទីកន្លែង(?:កំណើត)?|កន្លែងកំណើត|អាសយដ្ឋាន|អាសឃដ្ឋាន|address|residence)',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(RegExp(r'[,:：;។]+'), ' ');
    final values = <String>[];
    for (final part in withoutLabels.split(RegExp(r'\s+'))) {
      var value =
          part
              .replaceAll(
                RegExp(r'^(?:ភូមិ|ឃុំ|សង្កាត់|ស្រុក|ខណ្ឌ|ក្រុង|ខេត្ត)'),
                '',
              )
              .replaceAll(RegExp(r'[^\u1780-\u17FF]'), '')
              .trim();
      if (value.length < 2 || values.contains(value)) continue;
      values.add(value);
    }
    return values.join(', ');
  }

  RegExpMatch? _findMrzName(String text) {
    for (final line in text.split(RegExp(r'\r?\n'))) {
      final compactLine = line.replaceAll(RegExp(r'[^A-Z<]'), '');
      final match = RegExp(
        r'^([A-Z]{2,})<<([A-Z]{2,})(?:<|$)',
      ).firstMatch(compactLine);
      if (match != null && !compactLine.startsWith('IDKHM')) {
        return match;
      }
    }
    return null;
  }

  Future<String> _readTextAtUsefulScales(File imageFile) async {
    final texts = <String>[];
    final original = await _localRecognizer.processImage(
      mlkit.InputImage.fromFilePath(imageFile.path),
    );
    texts.add(original.text);

    // Small ID-card labels are often missed at the crop's native size. Read
    // an enlarged copy as a second pass without requiring network OCR.
    final bytes = await imageFile.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return texts.join('\n');
    final enlarged = img.copyResize(
      decoded,
      width: decoded.width < 2200 ? 2200 : decoded.width,
    );
    final directory = await getTemporaryDirectory();
    final enlargedFile = File(
      '${directory.path}/ocr_enlarged_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await enlargedFile.writeAsBytes(img.encodeJpg(enlarged, quality: 95));
    try {
      final enlargedResult = await _localRecognizer.processImage(
        mlkit.InputImage.fromFilePath(enlargedFile.path),
      );
      texts.add(enlargedResult.text);
    } finally {
      try {
        await enlargedFile.delete();
      } catch (_) {
        // Temporary OCR files are best-effort cleanup.
      }
    }
    return texts.join('\n');
  }

  void _extractPlaceAndAddress(String text, List<String> values) {
    final lines =
        text
            .split(RegExp(r'\r?\n'))
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .toList();
    final usableLines =
        lines.where((line) {
          final compactLine = line.replaceAll(RegExp(r'[^A-Z0-9<]'), '');
          return !RegExp(r'(?:IDKHM|LDKHM|TDKHM)').hasMatch(compactLine) &&
              !RegExp(r'^[0-9<MF]+$').hasMatch(compactLine) &&
              !RegExp(r'^\d{4}[-/.]\d{2}[-/.]\d{2}$').hasMatch(line);
        }).toList();

    for (var i = 0; i < usableLines.length; i++) {
      final normalized = usableLines[i].toLowerCase();
      final isPlaceOfBirthLine = RegExp(
        r'place\s+of\s+birth|birth\s+place|ទីកន្លែង(?:កំណើត)?|កន្លែងកំណើត|កំណើត',
      ).hasMatch(normalized);
      final isAddressLine = RegExp(
        r'address|residence|អាស.{0,6}ដ្ឋាន',
      ).hasMatch(normalized);

      if (values[6].isEmpty && isPlaceOfBirthLine) {
        final candidate =
            _valueAfterLabel(usableLines[i], isPlaceOfBirth: true) ??
            _nextMeaningfulLine(usableLines, i);
        if (_isFieldValue(candidate, isPlaceOfBirth: true)) {
          values[6] = candidate!;
        }
      }
      if (values[7].isEmpty && isAddressLine) {
        var candidate =
            _valueAfterLabel(usableLines[i]) ??
            _nextMeaningfulLine(usableLines, i);
        final nextLine = _nextMeaningfulLine(usableLines, i);
        if (candidate != null && nextLine != null && nextLine != candidate) {
          candidate = '$candidate, $nextLine';
        }
        if (_isFieldValue(candidate)) {
          values[7] = candidate!;
        }
      }
    }

    if (values[6].isEmpty) {
      for (final line in usableLines) {
        final normalized = line.toLowerCase();
        final looksLikeLocation =
            normalized.contains('ស្រុក') ||
            normalized.contains('ខណ្ឌ') ||
            normalized.contains('តាកែវ');
        final looksLikeAddress =
            normalized.contains('ភូមិ') ||
            normalized.contains('ឃុំ') ||
            RegExp(r'address|residence|អាស').hasMatch(normalized);
        if (looksLikeLocation && !looksLikeAddress) {
          final value = _removeFieldLabel(line);
          if (_isFieldValue(value, isPlaceOfBirth: true)) {
            values[6] = value;
            break;
          }
        }
      }
    }
  }

  String _removeFieldLabel(String line) {
    return line
        .replaceFirst(
          RegExp(
            r'^(?:place\s+of\s+birth|birth\s+place|ទីកន្លែង(?:កំណើត)?|កន្លែងកំណើត|កំណើត)\s*[:：ៈ-]?\s*',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
  }

  bool _isFieldValue(String? value, {bool isPlaceOfBirth = false}) {
    if (value == null || value.trim().isEmpty) return false;
    final normalized = value.trim().toLowerCase();
    if (isPlaceOfBirth &&
        RegExp(r'^(place\s+of\s+birth|birth\s+place)$').hasMatch(normalized)) {
      return false;
    }
    if (!isPlaceOfBirth &&
        RegExp(r'^(address|residence)$').hasMatch(normalized)) {
      return false;
    }
    return true;
  }

  String? _valueAfterLabel(String line, {bool isPlaceOfBirth = false}) {
    final label =
        isPlaceOfBirth
            ? r'(?:place\s+of\s+birth|birth\s+place|ទីកន្លែង(?:កំណើត)?|កន្លែងកំណើត|កំណើត)'
            : r'(?:address|residence|អាស.{0,6}ដ្ឋាន)';
    final match = RegExp(
      '$label(?:\\s*[:：ៈ-]\\s*|\\s+)(.+)',
      caseSensitive: false,
    ).firstMatch(line);
    final value = match?.group(1)?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  String? _nextMeaningfulLine(List<String> lines, int index) {
    for (var i = index + 1; i < lines.length; i++) {
      if (lines[i].length >= 3) return lines[i];
    }
    return null;
  }

  String _formatMrzDate(String value, {bool isExpiry = false}) {
    final year = int.parse(value.substring(0, 2));
    final fullYear = isExpiry || year <= 30 ? 2000 + year : 1900 + year;
    return '$fullYear-${value.substring(2, 4)}-${value.substring(4, 6)}';
  }
}
