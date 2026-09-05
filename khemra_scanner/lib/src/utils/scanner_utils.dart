/// Utility helpers for the KhemraScanner package.
abstract final class ScannerUtils {
  /// Normalizes a string key by lowercasing and removing non-alphanumeric chars.
  static String normalizeKey(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// Returns true if the given [value] is a valid YYYY-MM-DD date string.
  static bool isValidDate(String value) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (match == null) return false;
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    if (month < 1 || month > 12 || day < 1) return false;
    final parsed = DateTime(year, month, day);
    return parsed.year == year &&
        parsed.month == month &&
        parsed.day == day;
  }

  /// Converts a 6-digit MRZ date string (YYMMDD) to YYYY-MM-DD format.
  static String formatMrzDate(String value) {
    final year = int.parse(value.substring(0, 2));
    final fullYear = year <= 50 ? 2000 + year : 1900 + year;
    return '$fullYear-${value.substring(2, 4)}-${value.substring(4, 6)}';
  }

  /// Calculates the appropriate line height for text based on whether it
  /// contains Khmer characters (Unicode range U+1780–U+17FF).
  static double lineHeight(String text) {
    return RegExp(r'[\u1780-\u17FF]').hasMatch(text) ? 1.6 : 1.3;
  }

  /// Validates a Cambodian national ID card field value for the given [index].
  ///
  /// Returns null if the value is valid, or an error message string otherwise.
  static String? fieldValidationError(int index, String value) {
    final text = value.trim();
    switch (index) {
      case 0:
        return RegExp(r'^\d{9}$').hasMatch(text)
            ? null
            : 'Enter the 9-digit ID number.';
      case 1:
        return text.length >= 2 && RegExp(r'[^\d]').hasMatch(text)
            ? null
            : 'Enter the card holder name.';
      case 2:
      case 3:
        return isValidDate(text)
            ? null
            : 'Enter a valid date in YYYY-MM-DD format.';
      case 4:
        return const {'male', 'female', 'm', 'f'}.contains(text.toLowerCase())
            ? null
            : 'Enter Male, Female, M, or F.';
      default:
        return null;
    }
  }
}
