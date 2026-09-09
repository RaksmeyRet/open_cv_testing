import 'package:flutter_test/flutter_test.dart';
import 'package:native_opencv_kit_example/models/id_card_data.dart';

void main() {
  test('provides the default Cambodian ID card labels', () {
    final result = IdCardData.defaults();

    expect(result.fieldLabels, contains('ID number'));
    expect(result.fieldLabels, contains('Gender'));
    expect(result.fieldLabelsKhmer, hasLength(result.fieldLabels.length));
  });
}
