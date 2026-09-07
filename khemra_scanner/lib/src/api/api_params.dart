abstract final class ApiParams {
  // Headers
  static const String authorization = 'Authorization';
  static const String tokenHeader = 'Bearer';
  static const String contentType = 'Content-Type';
  static const String accept = 'Accept';
  static const String formData = 'multipart/form-data';
  static const String applicationJson = 'application/json';

  // Timeout
  static const int timeoutSendData = 45; // seconds

  // Error response keys
  static const String errors = 'errors';
  static const String devCode = 'devCode';
  static const String text = 'text';

  // Error codes & messages
  static const int errTimeoutCode = 408;
  static const String connectionTimeout = 'Connection timeout.';

  static const int errConnectionCode = 503;
  static const String connectionLost = 'No internet connection.';

  static const int errLocalCode = 500;
  static const String localErr = 'Something went wrong. Please try again.';
}
