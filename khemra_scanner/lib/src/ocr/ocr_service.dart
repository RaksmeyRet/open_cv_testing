import 'dart:io';

import 'package:http/http.dart' as http;
import 'dart:convert';

import '../models/khemra_scan_result.dart';
import 'text_recognizer.dart';

/// Result of an OCR service call.
class OcrServiceResult {
  const OcrServiceResult({required this.values, this.error});

  /// Extracted field values (same order as [IdCardData.defaultFieldLabels]).
  final List<String> values;

  /// Non-null if the OCR call failed.
  final String? error;

  bool get isSuccess => error == null;
}

/// Service that sends an image file to the remote OCR backend and returns
/// a structured [KhemraScanResult].
class OcrService {
  OcrService({required this.baseUrl});

  /// Base URL of the OCR server, e.g. `http://157.245.49.153:8212`.
  final String baseUrl;

  final _recognizer = TextRecognizer();

  static const int _fieldCount = 5;

  /// Calls the OCR API with [imageFile] and returns an [OcrServiceResult].
  Future<OcrServiceResult> recognize(File imageFile) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/api/ocr/id-card/'),
      )
        ..fields['language'] = 'eng+khm'
        ..files.add(
          await http.MultipartFile.fromPath('file', imageFile.path),
        );

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 45),
      );
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode != 200) {
        throw Exception(
          'OCR failed (HTTP ${response.statusCode}): ${response.body}',
        );
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final fields = _recognizer.extractFields(decoded);
      _recognizer.fillMissingMrzFields(fields, decoded);

      final mrzId = _recognizer.findMrzId(decoded);
      if (mrzId != null) {
        fields['idnumber'] = mrzId;
      }

      final rawMrzId = _recognizer.findRawMrzId(decoded['raw_text']);
      if (_recognizer.fieldValue(fields, 0).isEmpty && rawMrzId != null) {
        fields['idnumber'] = rawMrzId;
      }

      final values = List.generate(
        _fieldCount,
        (index) => _recognizer.fieldValue(fields, index),
      );

      final hasRecognizedValue = values.any((v) => v.isNotEmpty);
      if (!hasRecognizedValue) {
        throw Exception('OCR returned no recognizable ID-card fields');
      }

      return OcrServiceResult(values: values);
    } catch (error) {
      return OcrServiceResult(
        values: List.filled(_fieldCount, ''),
        error:
            'Could not connect to the OCR backend at $baseUrl. '
            'Make this URL reachable from the phone, then try again.\n$error',
      );
    }
  }

  /// Converts an [OcrServiceResult] to a [KhemraScanResult].
  KhemraScanResult toScanResult(OcrServiceResult result) {
    return KhemraScanResult(
      idNumber: result.values.isNotEmpty ? result.values[0] : null,
      name: result.values.length > 1 ? result.values[1] : null,
      dateOfBirth: result.values.length > 2 ? result.values[2] : null,
      expiryDate: result.values.length > 3 ? result.values[3] : null,
      gender: result.values.length > 4 ? result.values[4] : null,
    );
  }
}
