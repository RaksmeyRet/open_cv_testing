/// Result model returned after a successful ID card scan.
class KhemraScanResult {
  const KhemraScanResult({
    this.idNumber,
    this.name,
    this.dateOfBirth,
    this.expiryDate,
    this.gender,
  });

  final String? idNumber;
  final String? name;
  final String? dateOfBirth;
  final String? expiryDate;
  final String? gender;

  factory KhemraScanResult.fromJson(Map<String, dynamic> json) {
    return KhemraScanResult(
      idNumber: json['ID number'] ?? json['idnumber'] ?? json['idNumber'],
      name: json['Name'] ?? json['name'] ?? json['fullname'],
      dateOfBirth:
          json['Date of birth'] ?? json['dateofbirth'] ?? json['dob'],
      expiryDate:
          json['Expiry date'] ?? json['expirydate'] ?? json['expiry'],
      gender: json['Gender'] ?? json['gender'] ?? json['sex'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ID number': idNumber,
      'Name': name,
      'Date of birth': dateOfBirth,
      'Expiry date': expiryDate,
      'Gender': gender,
    };
  }

  static List<KhemraScanResult> parseList(List<dynamic> list) {
    return list
        .map(
          (item) =>
              KhemraScanResult.fromJson(item as Map<String, dynamic>),
        )
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
