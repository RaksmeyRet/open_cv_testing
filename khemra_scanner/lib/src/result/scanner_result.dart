/// The outcome of a scanner capture.
class KhemraScannerResult {
  final String? imagePath;
  final bool isValid;

  const KhemraScannerResult({
    this.imagePath,
    required this.isValid,
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
