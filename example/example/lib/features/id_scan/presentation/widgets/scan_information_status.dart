import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/widgets/my_text.dart';

class ScanInformationStatus extends StatelessWidget {
  const ScanInformationStatus({
    required this.completedCount,
    required this.missingLabels,
    super.key,
  });

  final int completedCount;
  final List<String> missingLabels;

  static const _totalFields = 5;

  bool get _isComplete => completedCount == _totalFields;

  @override
  Widget build(BuildContext context) {
    final statusColor =
        _isComplete ? AppColors.primaryColor : AppColors.redColor;
    final statusText =
        _isComplete
            ? 'ព័ត៌មានអត្តសញ្ញាណប័ណ្ណគ្រប់គ្រាន់'
            : 'សូមបំពេញព័ត៌មានដែលនៅខ្វះ';
    final detailText =
        _isComplete
            ? 'បានបំពេញ $_totalFields/$_totalFields មុខរួចរាល់'
            : 'បានបំពេញ $completedCount/$_totalFields មុខ';

    return Semantics(
      label: '$statusText។ $detailText',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: statusColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: statusColor.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _isComplete ? Icons.check_circle_outline : Icons.info_outline,
                  color: statusColor,
                ),
                const SizedBox(width: 8),
                Expanded(child: MyText.label(statusText, color: statusColor)),
                Text(
                  '$completedCount/$_totalFields',
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            MyText.description(
              _isComplete || missingLabels.isEmpty
                  ? detailText
                  : '$detailText: ${missingLabels.join(', ')}',
              maxLines: 3,
            ),
          ],
        ),
      ),
    );
  }
}
