class ScanResultModel {
  String? idNumber;
  String? name;
  String? dateOfBirth;
  String? expiryDate;
  String? gender;

  ScanResultModel({
    this.idNumber,
    this.name,
    this.dateOfBirth,
    this.expiryDate,
    this.gender,
  });

  ScanResultModel.fromJson(Map<String, dynamic> json) {
    idNumber = json['ID number'] ?? json['idnumber'] ?? json['idNumber'];
    name = json['Name'] ?? json['name'] ?? json['fullname'];
    dateOfBirth = json['Date of birth'] ?? json['dateofbirth'] ?? json['dob'];
    expiryDate = json['Expiry date'] ?? json['expirydate'] ?? json['expiry'];
    gender = json['Gender'] ?? json['gender'] ?? json['sex'];
  }

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{};

    data['ID number'] = idNumber;
    data['Name'] = name;
    data['Date of birth'] = dateOfBirth;
    data['Expiry date'] = expiryDate;
    data['Gender'] = gender;

    return data;
  }

  static List<ScanResultModel> parsed(List<dynamic> list) {
    return list.map((item) => ScanResultModel.fromJson(item)).toList();
  }

  Map<String, String> toDisplayMap() {
    final map = <String, String>{};
    final json = toJson();

    json.forEach((key, value) {
      if (value != null) {
        map[key] = value.toString();
      }
    });

    return map;
  }
}
