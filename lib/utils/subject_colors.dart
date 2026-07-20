import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Fixed palette cycled by subject order, shared between the mock exam
/// intro table and its สารบัญ picker so both use the same colors.
const List<Color> mockExamSubjectPalette = [
  AppColors.blueDark,
  AppColors.green,
  AppColors.gold,
  AppColors.red,
  Color(0xFF8B5CF6),
  Color(0xFF0EA5A4),
];

/// Assigns each subject a stable color by its first-appearance order in
/// [orderedTitles] (deduplicated).
Color subjectColorFor(String title, List<String> orderedTitles) {
  final unique = <String>[];
  for (final t in orderedTitles) {
    if (!unique.contains(t)) unique.add(t);
  }
  final index = unique.indexOf(title);
  if (index < 0) return AppColors.inkFaint;
  return mockExamSubjectPalette[index % mockExamSubjectPalette.length];
}
