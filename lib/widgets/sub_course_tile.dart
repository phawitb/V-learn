import 'package:flutter/material.dart';

import '../models/mission_node.dart';
import '../theme/app_theme.dart';
import '../utils/relative_time.dart';
import 'thin_progress_bar.dart';

/// One subject row inside a main course's eggspace section — each subject
/// is its own sub-course with independent progress, even though enrollment
/// (and the countdown/expiry) lives on the parent main course.
class SubCourseTile extends StatelessWidget {
  final MissionUnit unit;
  final VoidCallback onTap;

  /// Parent main-course label (e.g. "ก.พ. ภาค ก."), shown when subjects
  /// from several main courses are listed together so same-named subjects
  /// (e.g. "ภาษาไทย" appears in more than one main course) stay disambiguated.
  final String? subtitle;

  /// True for the single subject the learner most recently answered a
  /// question in — gets a red frame and a "x ago" label so it's easy to
  /// spot where to pick back up.
  final bool isRecent;

  const SubCourseTile({super.key, required this.unit, required this.onTap, this.subtitle, this.isRecent = false});

  @override
  Widget build(BuildContext context) {
    final done = unit.answeredCount == unit.questions.length && unit.questions.isNotEmpty;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isRecent ? AppColors.red : AppColors.border, width: isRecent ? 1.6 : 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: done ? AppColors.goldSoft : AppColors.surfaceSoft,
                shape: BoxShape.circle,
              ),
              child: Text(done ? '🏆' : '🥚', style: const TextStyle(fontSize: 15)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10.5, color: AppColors.inkFaint, fontWeight: FontWeight.w700),
                      ),
                    ),
                  Text(
                    unit.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: AppColors.ink),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(child: ThinProgressBar(value: unit.progress, height: 4)),
                      const SizedBox(width: 8),
                      Text(
                        '${unit.answeredCount}/${unit.questions.length} ข้อ',
                        style: const TextStyle(fontSize: 10.5, color: AppColors.inkFaint, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (isRecent && unit.lastActivityAt != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      relativeTimeLabel(unit.lastActivityAt!),
                      style: const TextStyle(fontSize: 10, color: AppColors.red, fontWeight: FontWeight.w700),
                    ),
                  ),
                Text(
                  '${(unit.progress * 100).round()}%',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.inkSoft, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
