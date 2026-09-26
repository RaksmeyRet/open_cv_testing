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
    return KhemraScanResult(
      idNumber: json['id_number'],
      surname: json['surname_en'],
      username: json['username_en'],
      dateOfBirth: json['date_of_birth'],
      expiryDate: json['expiry_date'],
      gender: json['gender'],
      placeOfBirth: json['place_of_birth'],
      address: json['address'],
    );
  }

  static List<KhemraScanResult> parseList(List<dynamic> list) {
    return list
        .map((item) => KhemraScanResult.fromJson(item as Map<String, dynamic>))
        .toList();
  }

}
