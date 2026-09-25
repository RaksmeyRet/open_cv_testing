/// Result model returned after a successful ID card scan.
class KhemraScanResult {
  const KhemraScanResult({
    this.idNumber,
    this.surname,
    this.username,
    this.dateOfBirth,
    this.expiryDate,
    this.gender,
    this.placeOfBirth,
    this.address,
  });

  final String? idNumber;
  final String? surname;
  final String? username;
  final String? dateOfBirth;
  final String? expiryDate;
  final String? gender;
  final String? placeOfBirth;
  final String? address;

  String? get name => [
    surname,
    username,
  ].where((value) => value != null && value.trim().isNotEmpty).join(' ');

  factory KhemraScanResult.fromJson(Map<String, dynamic> json) {
    final fields = <String, dynamic>{};

    void collect(dynamic source) {
      if (source is Map) {
        for (final entry in source.entries) {
          final key = entry.key.toString();
          final value = entry.value;
          if (value is Map || value is List) {
            collect(value);
          }
          fields[key] = value;
        }
      } else if (source is List) {
        for (final item in source) {
          collect(item);
        }
      }
    }

    collect(json);

    String? value(List<String> keys) {
      for (final key in keys) {
        final candidate = fields[key];
        if (candidate != null && '$candidate'.trim().isNotEmpty) {
          return '$candidate'.trim();
        }
      }
      return null;
    }

    return KhemraScanResult(
      idNumber: value(['ID number', 'id_number', 'idnumber', 'idNumber']),
      surname: value(['Surname', 'surname_en', 'surname', 'last_name']),
      username: value(['Username', 'username_en', 'username', 'given_name']),
      dateOfBirth: value([
        'Date of birth',
        'date_of_birth',
        'dateofbirth',
        'dob',
      ]),
      expiryDate: value(['Expiry date', 'expiry_date', 'expirydate', 'expiry']),
      gender: value(['Gender', 'gender', 'sex']),
      placeOfBirth: value([
        'Place of birth',
        'place_of_birth',
        'placeofbirth',
        'birth_place',
        'birthplace',
        'location_of_birth',
      ]),
      address: value([
        'Address',
        'address',
        'home_address',
        'current_address',
        'residence',
      ]),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ID number': idNumber,
      'Surname': surname,
      'Username': username,
      'Date of birth': dateOfBirth,
      'Expiry date': expiryDate,
      'Gender': gender,
      'Place of birth': placeOfBirth,
      'Address': address,
    };
  }

  static List<KhemraScanResult> parseList(List<dynamic> list) {
    return list
        .map((item) => KhemraScanResult.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// Returns a display-friendly map of non-null fields.
  Map<String, String> toDisplayMap() {
    return {
      for (final entry in toJson().entries)
        if (entry.value != null) entry.key: entry.value.toString(),
    };
  }

  @override
  String toString() => 'KhemraScanResult(${toJson()})';
}
