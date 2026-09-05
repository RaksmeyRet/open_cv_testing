import 'package:flutter/material.dart';

/// A status card that shows how many ID card fields have been recognised and
/// lists any missing field labels.
///
/// Example:
/// ```dart
/// ScannerInstruction(
///   completedCount: 3,
///   missingLabels: ['Date of birth', 'Gender'],
/// )
/// ```
class ScannerInstruction extends StatelessWidget {
  const ScannerInstruction({
    required this.completedCount,
    required this.missingLabels,
    this.totalFields = 5,
    this.completeText = 'ព័ត៌មានអត្តសញ្ញាណប័ណ្ណគ្រប់គ្រាន់',
    this.incompleteText = 'សូមបំពេញព័ត៌មានដែលនៅខ្វះ',
    this.primaryColor = const Color(0xFF092469),
    this.errorColor = const Color(0xFFE53935),
    super.key,
  });

  /// Number of fields that have been successfully extracted.
  final int completedCount;

  /// Labels of the fields that are still missing.
  final List<String> missingLabels;

  /// Total number of expected fields. Defaults to 5.
  final int totalFields;

  final String completeText;
  final String incompleteText;
  final Color primaryColor;
  final Color errorColor;

  bool get _isComplete => completedCount == totalFields;

  @override
  Widget build(BuildContext context) {
    final statusColor = _isComplete ? primaryColor : errorColor;
    final statusText = _isComplete ? completeText : incompleteText;
    final detailText = _isComplete
        ? 'បានបំពេញ $totalFields/$totalFields មុខរួចរាល់'
        : 'បានបំពេញ $completedCount/$totalFields មុខ';

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
                  _isComplete
                      ? Icons.check_circle_outline
                      : Icons.info_outline,
                  color: statusColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    statusText,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '$completedCount/$totalFields',
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _isComplete || missingLabels.isEmpty
                  ? detailText
                  : '$detailText: ${missingLabels.join(', ')}',
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF505050),
              ),
              maxLines: 3,
              overflow: TextOverflow.clip,
            ),
          ],
        ),
      ),
    );
  }
}

/// A small icon-button + label combo used in the camera controls bar.
class ScannerToolButton extends StatelessWidget {
  const ScannerToolButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.active = false,
    this.activeColor = const Color(0xFFCF951B),
    this.inactiveColor = const Color(0xFF505050),
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  /// Whether the button is in an "on" state (e.g. flash is enabled).
  final bool active;
  final Color activeColor;
  final Color inactiveColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: label,
          onPressed: onPressed,
          icon: Icon(icon),
          iconSize: 30,
          color: Colors.white,
          style: IconButton.styleFrom(
            backgroundColor: active ? activeColor : inactiveColor,
            fixedSize: const Size(50, 50),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
