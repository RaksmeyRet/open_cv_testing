import '../utils/scanner_utils.dart';

/// Parses and extracts structured ID card fields from a raw OCR response map.
class TextRecognizer {
  /// Field key lookup table ordered by field index (same order as [IdCardData.defaultFieldLabels]).
  static const List<List<String>> _fieldKeys = [
    [
      'idnumber',
      'idno',
      'idcardnumber',
      'identitynumber',
      'identityno',
      'documentnumber',
      'cardnumber',
    ],
    [
      'surname',
      'surname_en',
      'lastname',
      'last_name',
      'familyname',
      'full_name_en',
    ],
    [
      'username',
      'username_en',
      'givenname',
      'given_name',
      'firstname',
      'first_name',
      'name',
    ],
    ['dateofbirth', 'dob', 'birthdate', 'birth', 'datebirth'],
    [
      'expirydate',
      'expiry',
      'expirationdate',
      'expiration',
      'dateofexpiry',
      'validuntil',
    ],
    ['gender', 'sex', 'genderidentity'],
    ['placeofbirth', 'place_of_birth', 'birthplace', 'birth_place', 'pob'],
    ['address', 'residence', 'homeaddress', 'currentaddress'],
  ];

  /// Recursively walks the [response] JSON and collects all leaf values into
  /// a normalized key→value map.
  Map<String, String> extractFields(Map<String, dynamic> response) {
    final fields = <String, String>{};

    void visit(dynamic value, [String prefix = '']) {
      if (value is Map) {
        value.forEach((key, child) {
          final name = ScannerUtils.normalizeKey('$key');
          if (child is Map || child is List) {
            visit(child, name);
          } else if (child != null) {
            final text = '$child'.trim();
            if (text.isNotEmpty && text != 'null') {
              fields[name] = text;
              if (prefix.isNotEmpty) fields['$prefix$name'] = text;
            }
          }
        });
      } else if (value is List) {
        for (final child in value) {
          visit(child, prefix);
        }
      }
    }

    visit(response);
    return fields;
  }

  /// Returns the first non-empty value from [fields] that matches one of the
  /// canonical keys for the field at position [index].
  String fieldValue(Map<String, String> fields, int index) {
    for (final key in _fieldKeys[index]) {
      final value = fields[ScannerUtils.normalizeKey(key)];
      if (value != null && value.trim().isNotEmpty && value != 'null') {
        return value.trim();
      }
    }
    return '';
  }

  /// Attempts to fill missing MRZ-parseable fields (ID number, date of birth)
  /// from the raw text in [response].
  void fillMissingMrzFields(
    Map<String, String> fields,
    Map<String, dynamic> response,
  ) {
    final rawText = _findRawText(response).toUpperCase();
    if (rawText.isEmpty) return;

    final normalizedText = rawText.replaceAll(RegExp(r'[^A-Z0-9<]'), '');
    final idMatch = RegExp(
      r'(?:IDKHM|LDKHM|TDKHM)([0-9O]{9})[0-9O]',
    ).firstMatch(normalizedText);
    if (fieldValue(fields, 0).isEmpty && idMatch != null) {
      fields['idnumber'] = idMatch.group(1)!.replaceAll('O', '0');
    }

    final dateMatch = RegExp(r'([0-9]{6})[0-9][MF]').firstMatch(normalizedText);
    if (fieldValue(fields, 2).isEmpty && dateMatch != null) {
      fields['dateofbirth'] = ScannerUtils.formatMrzDate(dateMatch.group(1)!);
    }
  }

  /// Searches recursively through [value] for an MRZ-style Cambodian ID number.
  String? findMrzId(dynamic value) {
    String? found;

    void visit(dynamic child) {
      if (found != null) return;
      if (child is String) {
        final normalized = child.toUpperCase().replaceAll(' ', '');
        final match = RegExp(
          r'IDKHM[^0-9O]{0,4}([0-9O]{9})[0-9O]',
        ).firstMatch(normalized);
        if (match != null) {
          found = match.group(1)!.replaceAll('O', '0');
        }
      } else if (child is Map) {
        for (final item in child.values) {
          visit(item);
          if (found != null) return;
        }
      } else if (child is List) {
        for (final item in child) {
          visit(item);
          if (found != null) return;
        }
      }
    }

    visit(value);
    return found;
  }

  /// Extracts a 9-digit ID number from raw MRZ lines in [value].
  String? findRawMrzId(dynamic value) {
    final text = _findRawText(value);
    if (text.isEmpty) return null;
    for (final line in text.toUpperCase().split(RegExp(r'\r?\n'))) {
      final compact = line.replaceAll(RegExp(r'[^0-9]'), '');
      if (line.contains('<<') && compact.length >= 10) {
        final lastTen = compact.substring(compact.length - 10);
        return lastTen.substring(0, 9);
      }
    }
    return null;
  }

  String _findRawText(dynamic value) {
    final matches = <String>[];

    void visit(dynamic child, [String? key]) {
      if (child is String) {
        final normalizedKey = ScannerUtils.normalizeKey(key ?? '');
        if (key == null ||
            normalizedKey == 'rawtext' ||
            normalizedKey == 'ocrtext' ||
            normalizedKey == 'text') {
          final text = child.trim();
          if (text.isNotEmpty) matches.add(text);
        }
        return;
      }
      if (child is Map) {
        child.forEach((childKey, nested) {
          visit(nested, '$childKey');
        });
        return;
      }
      if (child is List) {
        for (final nested in child) {
          visit(nested, key);
        }
      }
    }

    visit(value);
    return matches.join('\n');
  }
}
