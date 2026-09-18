import 'dart:io';

import 'package:http/http.dart' as http;
import 'dart:convert';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart'
  as mlkit;

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
  final _localRecognizer = mlkit.TextRecognizer(
    script: mlkit.TextRecognitionScript.latin,
  );

  static const int _fieldCount = 5;

  /// Calls the OCR API with [imageFile] and returns an [OcrServiceResult].
  Future<OcrServiceResult> recognize(File imageFile) async {
    try {
      final response = await _sendRequest(imageFile, fieldName: 'file');
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_formatHttpError(response));
      }

      final decoded = _decodeJsonObject(response.body);
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
      final localResult = await _recognizeLocally(imageFile);
      if (localResult != null) return localResult;
      return OcrServiceResult(
        values: List.filled(_fieldCount, ''),
        error: _formatFailure(error),
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
        values[1] = '${nameMatch.group(1)} ${nameMatch.group(2)}';
      }
      if (personalMatch != null) {
        values[2] = _formatMrzDate(personalMatch.group(1)!);
        values[3] = _formatMrzDate(personalMatch.group(3)!, isExpiry: true);
        values[4] = personalMatch.group(2)!;
      }

      if (values.any((value) => value.isNotEmpty)) {
        return OcrServiceResult(values: values);
      }
    } catch (_) {
      // Keep the server error when on-device OCR is unavailable.
    }
    return null;
  }

  String _formatMrzDate(String value, {bool isExpiry = false}) {
    final year = int.parse(value.substring(0, 2));
    final fullYear = isExpiry || year <= 30 ? 2000 + year : 1900 + year;
    return '$fullYear-${value.substring(2, 4)}-${value.substring(4, 6)}';
  }

  String _formatFailure(Object error) {
    final message = error.toString();
    if (message.startsWith('Exception: ')) {
      return message.substring('Exception: '.length);
    }
    return 'Could not reach the OCR backend at $baseUrl.\n$message';
  }

  Future<http.Response> _sendRequest(
    File imageFile, {
    required String fieldName,
  }) async {
    final request =
        http.MultipartRequest('POST', Uri.parse('$baseUrl/api/ocr/id-card/'))
          ..fields['language'] = 'eng+khm'
          ..files.add(
            await http.MultipartFile.fromPath(fieldName, imageFile.path),
          );

    final streamedResponse = await request.send().timeout(
      const Duration(seconds: 45),
    );
    return http.Response.fromStream(streamedResponse);
  }

  Map<String, dynamic> _decodeJsonObject(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('OCR returned an invalid JSON response');
    }
    return decoded;
  }

  String _formatHttpError(http.Response response) {
    final contentType = response.headers['content-type'] ?? '';
    if (contentType.contains('json')) {
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) {
          final detail =
              decoded['detail'] ?? decoded['message'] ?? decoded['error'];
          if (detail != null) return 'OCR server error: $detail';
        }
      } on FormatException {
        // Fall through to the generic status message.
      }
    }

    if (contentType.contains('html')) {
      final exception = _extractHtmlException(response.body);
      if (exception != null) {
        return 'OCR server error (HTTP ${response.statusCode}): $exception';
      }
      return 'OCR server error (HTTP ${response.statusCode}). The server returned an HTML error page.';
    }
    return 'OCR server error (HTTP ${response.statusCode}).';
  }

  String? _extractHtmlException(String body) {
    if (body.contains('could not translate host name') &&
        body.contains('Temporary failure in name resolution')) {
      return 'OCR backend database is unavailable';
    }

    final match = RegExp(
      r'Exception Type:</th>.*?<td[^>]*>([^<]+)</td>.*?'
      r'Exception Value:</th>.*?<td[^>]*><pre>(.*?)</pre>',
      dotAll: true,
    ).firstMatch(body);
    if (match == null) return null;

    final type = _decodeHtml(match.group(1)!);
    final value =
        _decodeHtml(match.group(2)!).replaceAll(RegExp(r'\s+'), ' ').trim();
    return '$type: $value';
  }

  String _decodeHtml(String value) {
    return value
        .replaceAll('&quot;', '"')
        .replaceAll('&#x27;', "'")
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');
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
