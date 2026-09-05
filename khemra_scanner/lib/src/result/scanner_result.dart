import 'dart:typed_data';

/// The outcome of a scanner capture.
class KhemraScannerResult {
  final String? imagePath;
  final bool isValid;
  final Uint8List? imageBytes;

  const KhemraScannerResult({
    this.imagePath,
    required this.isValid,
    this.imageBytes,
  });
}

/// A user-facing scanner failure.
class KhemraScannerException implements Exception {
  final String message;
  final Object? cause;

  const KhemraScannerException(this.message, {this.cause});

  @override
  String toString() => 'KhemraScannerException: $message';
}
