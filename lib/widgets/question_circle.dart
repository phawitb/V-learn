import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// One question on the eggspace mission path, shown as a small numbered
/// circle. There's no "set" to unlock anymore — every question is directly
/// tappable, and the circle's color reflects whether it's been answered and
/// whether that answer was correct. Small corner badges flag questions the
/// learner bookmarked or reported.
///
/// When [subjectColor] is given (mock exams span multiple subjects), it
/// takes over the circle's fill/border instead of the usual green/red, and
/// correctness moves to a small check/cross badge at the bottom-right
/// corner instead — so both signals stay visible at once.
class QuestionCircle extends StatelessWidget {
  final int number;
  final bool answered;
  final bool isCorrect;
  final bool saved;
  final bool reported;
  final Color? subjectColor;
  final VoidCallback onTap;

  const QuestionCircle({
    super.key,
    required this.number,
    required this.answered,
    required this.isCorrect,
    this.saved = false,
    this.reported = false,
    this.subjectColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool bySubject = subjectColor != null;
    final Color accent = bySubject ? subjectColor! : (isCorrect ? AppColors.green : AppColors.red);
    final Color fill = answered ? accent.withValues(alpha: bySubject ? 0.2 : 0.14) : Colors.white;
    final Color border = answered ? accent : AppColors.border;
    final Color textColor = answered ? accent : AppColors.ink;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 46,
        height: 46,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: fill,
                shape: BoxShape.circle,
                border: Border.all(color: border, width: 2),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 5, offset: const Offset(0, 2)),
                ],
              ),
              child: Text('$number', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: textColor)),
            ),
            if (bySubject && answered)
              Positioned(
                bottom: -3,
                right: -3,
                child: _Badge(
                  icon: isCorrect ? Icons.check_rounded : Icons.close_rounded,
                  color: isCorrect ? AppColors.green : AppColors.red,
                ),
              ),
            if (saved)
              Positioned(top: -3, right: reported ? 12 : -3, child: const _Badge(icon: Icons.bookmark_rounded, color: AppColors.gold)),
            if (reported)
              const Positioned(top: -3, right: -3, child: _Badge(icon: Icons.flag_rounded, color: AppColors.red)),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _Badge({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: 16,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 1.2),
      ),
      child: Icon(icon, size: 9, color: color),
    );
  }
}
