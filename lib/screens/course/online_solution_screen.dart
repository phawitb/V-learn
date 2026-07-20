import 'package:flutter/material.dart';

import '../../models/course.dart';
import '../../models/mission_node.dart';
import '../../theme/app_theme.dart';
import '../../widgets/latex_text.dart';

/// Read-only browsing of every question's detailed solution — the
/// "ดูเฉลยละเอียดได้ทุกเวลา" promise, separate from the interactive Step
/// Solution flow inside eggspace exercises. Pass [unit] to scope this to
/// one subject; omit it to browse every subject in [course].
class OnlineSolutionScreen extends StatelessWidget {
  final Course course;
  final MissionUnit? unit;

  const OnlineSolutionScreen({super.key, required this.course, this.unit});

  @override
  Widget build(BuildContext context) {
    final units = unit == null ? course.missionUnits : [unit!];
    final questions = units.expand((u) => u.questions).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(unit == null ? 'Online Solution' : 'Online Solution · ${unit!.title}')),
      body: questions.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'ยังไม่มีเฉลยออนไลน์สำหรับคอร์สนี้',
                  style: TextStyle(color: AppColors.inkFaint),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: questions.length,
              separatorBuilder: (_, __) => const SizedBox(height: 14),
              itemBuilder: (context, i) {
                final q = questions[i];
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(top: 8),
                    title: LatexText(
                      'ข้อ ${i + 1}: ${q.prompt}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: AppColors.ink),
                    ),
                    children: [
                      LatexText(
                        'เฉลย: ${q.choices[q.correctIndex]}',
                        style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.blueDark, fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      LatexText(q.stepSolution, style: const TextStyle(color: AppColors.inkSoft, fontSize: 13, height: 1.5)),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
