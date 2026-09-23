import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart'
    as mlkit;

import '../models/khemra_scan_result.dart';

/// Result of an OCR service call.
class OcrServiceResult {
  const OcrServiceResult({required this.values, this.error});

  /// Extracted field values (same order as [IdCardData.defaultFieldLabels]).
  final List<String> values;

  /// Non-null if the OCR call failed.
  final String? error;

  bool get isSuccess => error == null;
}

/// On-device OCR service using Google ML Kit.
class OcrService {
  OcrService();

  final _localRecognizer = mlkit.TextRecognizer(
    script: mlkit.TextRecognitionScript.latin,
  );

  static const int _fieldCount = 8;

  void dispose() {
    _localRecognizer.close();
  }

  /// Runs OCR locally on [imageFile] and returns an [OcrServiceResult].
  Future<OcrServiceResult> recognize(File imageFile) async {
    try {
      final result = await _recognizeLocally(imageFile);
      if (result != null) {
        return result;
      }
      return OcrServiceResult(
        values: List.filled(_fieldCount, ''),
        error: 'Local OCR could not recognize any ID-card fields.',
      );
    } catch (error) {
      return OcrServiceResult(
        values: List.filled(_fieldCount, ''),
        error: 'Local OCR failed: $error',
      );
    }
  }

  Future<OcrServiceResult?> _recognizeLocally(File imageFile) async {
    try {
      final recognized = await _localRecognizer.processImage(
        mlkit.InputImage.fromFilePath(imageFile.path),
      );
      final text = recognized.text.toUpperCase();
      final compact = text.replaceAll(RegExp(r'[^A-Z0-9<]'), '');
      final idMatch = RegExp(
        r'(?:IDKHM|LDKHM|TDKHM)([0-9O]{9})[0-9O]',
      ).firstMatch(compact);
      final personalMatch = RegExp(
        r'([0-9]{6})[0-9]([MF])([0-9]{6})[0-9]',
      ).firstMatch(compact);
      final nameMatch = RegExp(
        r'(?:^|\n)\s*([A-Z]+)<<([A-Z]+)(?:<<|\n|$)',
        multiLine: true,
      ).firstMatch(text);

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

      if (values.any((value) => value.isNotEmpty)) {
        return OcrServiceResult(values: values);
      }
    } catch (_) {
      // Return a failed result when on-device OCR is unavailable.
    }
    return null;
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
      if (values[6].isEmpty &&
          RegExp(r'place\s+of\s+birth|birth\s+place').hasMatch(normalized)) {
        values[6] = _nextMeaningfulLine(usableLines, i) ?? '';
      }
      if (values[7].isEmpty &&
          RegExp(r'address|residence').hasMatch(normalized)) {
        values[7] = _nextMeaningfulLine(usableLines, i) ?? '';
      }
    }
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

  /// Converts an [OcrServiceResult] to a [KhemraScanResult].
  KhemraScanResult toScanResult(OcrServiceResult result) {
    return KhemraScanResult(
      idNumber: result.values.isNotEmpty ? result.values[0] : null,
      surname: result.values.length > 1 ? result.values[1] : null,
      username: result.values.length > 2 ? result.values[2] : null,
      dateOfBirth: result.values.length > 3 ? result.values[3] : null,
      expiryDate: result.values.length > 4 ? result.values[4] : null,
      gender: result.values.length > 5 ? result.values[5] : null,
      placeOfBirth: result.values.length > 6 ? result.values[6] : null,
      address: result.values.length > 7 ? result.values[7] : null,
    );
  }
}
