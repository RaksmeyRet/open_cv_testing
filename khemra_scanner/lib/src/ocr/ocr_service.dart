import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:khemra_scanner/khemra_scanner.dart';
import 'package:khemra_scanner/src/api/api_client.dart';
import 'package:khemra_scanner/src/api/api_params.dart';

class OcrService {
  final _apiClient = ApiClient();
  OcrService();
  Future<ResponseIdCard> recognize(File imageFile) async {
    final response = await _apiClient.postFormData(
      'http://157.245.49.153:8212/api/ocr/id-card/',
      map: {'language': 'eng+khm'},
      files: [await http.MultipartFile.fromPath('file', imageFile.path)],
    );
    if (response.containsKey(ApiParams.errors)) {
      final err = response[ApiParams.errors] as Map<String, dynamic>;
      throw Exception(err[ApiParams.text] ?? 'Unknown error');
    }
    return ResponseIdCard.fromJson(response);
  }
}
