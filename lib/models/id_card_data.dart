class IdCardData {
  IdCardData({required this.fieldLabels, required this.fieldLabelsKhmer})
    : assert(
        fieldLabels.length == fieldLabelsKhmer.length,
        'fieldLabels and fieldLabelsKhmer must have the same length',
      );

  final List<String> fieldLabels;
  final List<String> fieldLabelsKhmer;

  factory IdCardData.defaults() => IdCardData(
    fieldLabels: const [
      'ID number',
      'Surname',
      'Username',
      'Date of birth',
      'Expiry date',
      'Gender',
      'Place of birth',
      'Address',
    ],
    fieldLabelsKhmer: const [
      'លេខអត្តសញ្ញាណ',
      'គោត្តនាម',
      'នាម',
      'ថ្ងៃខែឆ្នាំកំណើត',
      'ថ្ងៃផុតកំណត់',
      'ភេទ',
      'ទីកន្លែងកំណើត',
      'អាសយដ្ឋាន',
    ],
  );
}
