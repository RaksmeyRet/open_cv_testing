/// Structured data fields extracted from a Cambodian ID card.
class IdCardData {
  const IdCardData({
    required this.fieldLabels,
    required this.fieldLabelsKhmer,
  });

  final List<String> fieldLabels;
  final List<String> fieldLabelsKhmer;

  /// Default Cambodian ID card field labels (English).
  static const List<String> defaultFieldLabels = [
    'ID number',
    'Name',
    'Date of birth',
    'Expiry date',
    'Gender',
  ];

  /// Default Cambodian ID card field labels (Khmer).
  static const List<String> defaultFieldLabelsKhmer = [
    'លេខអត្តសញ្ញាណ',
    'គោត្តនាមនិងនាម',
    'ថ្ងៃខែឆ្នាំកំណើត',
    'ថ្ងៃផុតកំណត់',
    'ភេទ',
  ];

  factory IdCardData.defaults() => const IdCardData(
    fieldLabels: defaultFieldLabels,
    fieldLabelsKhmer: defaultFieldLabelsKhmer,
  );
}
