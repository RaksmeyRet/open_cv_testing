class IdCardData {
  const IdCardData({required this.fieldLabels, required this.fieldLabelsKhmer});

  final List<String> fieldLabels;
  final List<String> fieldLabelsKhmer;
  static const List<String> defaultFieldLabels = [
    'ID number',
    'Surname',
    'Username',
    'Date of birth',
    'Expiry date',
    'Gender',
    'Place of birth',
    'Address',
  ];

  /// Default Cambodian ID card field labels (Khmer).
  static const List<String> defaultFieldLabelsKhmer = [
    'លេខអត្តសញ្ញាណ',
    'គោត្តនាម',
    'នាម',
    'ថ្ងៃខែឆ្នាំកំណើត',
    'ថ្ងៃផុតកំណត់',
    'ភេទ',
    'ទីកន្លែងកំណើត',
    'អាសយដ្ឋាន',
  ];

  factory IdCardData.defaults() => const IdCardData(
    fieldLabels: defaultFieldLabels,
    fieldLabelsKhmer: defaultFieldLabelsKhmer,
  );
}
