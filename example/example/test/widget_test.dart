import 'package:flutter_test/flutter_test.dart';
import 'package:native_opencv_kit_example/features/id_scan/domain/entities/scan_result.dart';

void main() {
  test('reads OCR field aliases and omits empty display values', () {
    final result = ScanResultModel.fromJson({
      'idnumber': 'KHM123456789',
      'fullname': 'Sok Dara',
      'dob': '1990-01-01',
      'sex': 'M',
    });

    expect(result.idNumber, 'KHM123456789');
    expect(result.name, 'Sok Dara');
    expect(result.dateOfBirth, '1990-01-01');
    expect(result.expiryDate, isNull);
    expect(result.gender, 'M');
    expect(result.toDisplayMap(), {
      'ID number': 'KHM123456789',
      'Name': 'Sok Dara',
      'Date of birth': '1990-01-01',
      'Gender': 'M',
    });
  });
}
