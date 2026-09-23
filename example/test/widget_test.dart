import 'package:flutter_test/flutter_test.dart';
import 'package:native_opencv_kit_example/image/image_cropper.dart';
import 'package:native_opencv_kit_example/models/id_card_data.dart';
import 'package:native_opencv_kit_example/models/khemra_scan_result.dart';

void main() {
  test('provides the default Cambodian ID card labels', () {
    final result = IdCardData.defaults();

    expect(result.fieldLabels, contains('ID number'));
    expect(result.fieldLabels, contains('Gender'));
    expect(result.fieldLabelsKhmer, hasLength(result.fieldLabels.length));
  });

  test('normalizes card corners into clockwise order for a clean crop', () {
    final corners = <Offset>[
      const Offset(0.82, 0.18),
      const Offset(0.18, 0.14),
      const Offset(0.14, 0.82),
      const Offset(0.82, 0.76),
    ];

    final normalized = normalizeCardCorners(corners);

    expect(normalized.length, 4);
    expect(normalized[0], const Offset(0.18, 0.14));
    expect(normalized[1], const Offset(0.82, 0.18));
    expect(normalized[2], const Offset(0.82, 0.76));
    expect(normalized[3], const Offset(0.14, 0.82));
    expect(normalized[0].dx < normalized[1].dx, isTrue);
    expect(normalized[1].dy < normalized[2].dy, isTrue);
    expect(normalized[3].dx < normalized[2].dx, isTrue);
  });

  test('reads place of birth and address from extraction JSON', () {
    final result = KhemraScanResult.fromJson({
      'fields': {
        'place_of_birth': 'ត្រាំកក់, តាកែវ',
        'address': 'ត្រពាំងថ្ម, គុស, ត្រាំកក់, តាកែវ',
      },
    });

    expect(result.placeOfBirth, 'ត្រាំកក់, តាកែវ');
    expect(result.address, 'ត្រពាំងថ្ម, គុស, ត្រាំកក់, តាកែវ');
  });
}
