import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_params.dart';

class ResponseHelper {
  Map<String, dynamic> apiResponse(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
      return {
        ApiParams.errors: {
          ApiParams.devCode: response.statusCode,
          ApiParams.text: 'Invalid response format.',
        }
      };
    } catch (_) {
      return {
        ApiParams.errors: {
          ApiParams.devCode: ApiParams.errLocalCode,
          ApiParams.text: ApiParams.localErr,
        }
      };
    }
  }
}
