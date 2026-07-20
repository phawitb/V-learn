import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/mock_exam.dart';
import '../screens/exam/mock_exam_intro_screen.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/relative_time.dart';

/// Among sets with an in-progress attempt, only the single most recently
/// touched one gets the red "ทำล่าสุด" highlight — same rule as the
/// คลังข้อสอบ list's recency frame, so leaving several sets half-done
/// doesn't light up every card at once.
String? _mostRecentInProgressId(List<MockExamSet> sets) {
  MockExamSet? best;
  for (final s in sets) {
    if (!s.hasInProgress || s.lastActivityAt == null) continue;
    if (best == null || s.lastActivityAt!.isAfter(best.lastActivityAt!)) best = s;
  }
  return best?.id;
}

/// Home-screen entry point for the 2 pre-generated practice exams per
/// course. Hidden entirely if the course has none (e.g. no verified
/// content yet for that exam category).
class MockExamSection extends StatefulWidget {
  final String courseId;

  const MockExamSection({super.key, required this.courseId});

  @override
  State<MockExamSection> createState() => _MockExamSectionState();
}

class _MockExamSectionState extends State<MockExamSection> {
  late Future<List<MockExamSet>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<AppState>().loadMockExams(widget.courseId);
  }

  Future<void> _open(BuildContext context, MockExamSet set) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MockExamIntroScreen(examSet: set)),
    );
    if (!mounted) return;
    setState(() => _future = context.read<AppState>().loadMockExams(widget.courseId));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<MockExamSet>>(
      future: _future,
      builder: (context, snapshot) {
        final sets = snapshot.data ?? [];
        if (snapshot.connectionState == ConnectionState.done && sets.isEmpty) {
          return const SizedBox.shrink();
        }
        final recentId = _mostRecentInProgressId(sets);
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ข้อสอบเสมือนจริง', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              if (snapshot.connectionState != ConnectionState.done)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: LinearProgressIndicator(),
                )
              else
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < sets.length; i++) ...[
                        if (i > 0) const SizedBox(width: 10),
                        Expanded(
                          child: _ExamSetCard(
                            set: sets[i],
                            isRecent: sets[i].id == recentId,
                            onTap: () => _open(context, sets[i]),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ExamSetCard extends StatelessWidget {
  final MockExamSet set;
  final bool isRecent;
  final VoidCallback onTap;

  const _ExamSetCard({required this.set, required this.isRecent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isRecent ? AppColors.red : AppColors.border, width: isRecent ? 1.6 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.timer_outlined, size: 16, color: isRecent ? AppColors.red : AppColors.blueDark),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(set.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: AppColors.ink)),
                ),
                if (isRecent && set.lastActivityAt != null)
                  Text(
                    relativeTimeLabel(set.lastActivityAt!),
                    style: const TextStyle(fontSize: 10, color: AppColors.red, fontWeight: FontWeight.w700),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text('${set.totalQuestions} ข้อ · ${set.durationMinutes} นาที', style: const TextStyle(fontSize: 11, color: AppColors.inkFaint, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
