import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class ApiClient {
  final String baseUrl;

  ApiClient({
    required this.baseUrl,
  });

  Future<Map<String, dynamic>> postFormData(
    String url, {
    required Map<String, String> map,
    Map<String, String>? params,
    List<http.MultipartFile>? files,
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    try {
      final uri = Uri.parse(url).replace(
        queryParameters: params,
      );

      final request = http.MultipartRequest(
        'POST',
        uri,
      );
      if (headers != null) {
        request.headers.addAll(headers);
      }
      request.fields.addAll(map);

      if (files != null && files.isNotEmpty) {
        request.files.addAll(files);
      }
      final streamedResponse = await request.send().timeout(timeout);
      final response = await http.Response.fromStream(
        streamedResponse,
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Request failed with status ${response.statusCode}: '
          '${response.body}',
        );
      }
      final decoded = jsonDecode(response.body);

      if (decoded is! Map<String, dynamic>) {
        throw FormatException(
          'Invalid API response format.',
        );
      }
      return decoded;
    } on TimeoutException {
      throw Exception('Connection timeout.');
    } on SocketException {
      throw Exception('Connection lost.');
    } on HttpException catch (e) {
      throw Exception(e.message);
    }
  }
}

