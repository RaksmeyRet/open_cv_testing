/// Result model returned after a successful ID card scan.
class KhemraScanResult {
  final String? idNumber;
  final String? fullNameEN;
  final String? fullnameKH;
  final String? dateOfBirth;
  final String? expiryDate;
  final String? gender;
  final String? nationality;
  final String? address;

  const KhemraScanResult({
    this.idNumber,
    this.fullNameEN,
    this.fullnameKH,
    this.dateOfBirth,
    this.expiryDate,
    this.gender,
    this.nationality,
    this.address,
  });

  factory KhemraScanResult.fromJson(Map<String, dynamic> json) {
    return KhemraScanResult(
      idNumber: json['id_number'],
      fullNameEN: json['full_name_en'],
      fullnameKH: json['full_name_kh'],
      dateOfBirth: json['date_of_birth'],
      expiryDate: json['expiry_date'],
      gender: json['gender'],
      nationality: json['nationality'],
      address: json['address'],
    );
  }
}

class ResponseIdCard {
  int? id;
  String? cardType;
  KhemraScanResult? khemraScanResult;
  double? confindence;
  String? rawText;
  double? processingTimeMs;
  ResponseIdCard({
    this.id,
    this.cardType,
    this.khemraScanResult,
    this.confindence,
    this.rawText,
    this.processingTimeMs,
  });

  factory ResponseIdCard.fromJson(Map<String, dynamic> json) {
    return ResponseIdCard(
      id: json['id'],
      cardType: json['card_type'],
      khemraScanResult: json['fields'] == null
          ? null
          : KhemraScanResult.fromJson(json['fields']),
      confindence: json['confidence'],
      rawText: json['raw_text'],
      processingTimeMs: json['processing_time_ms'],
    );
  }
}
