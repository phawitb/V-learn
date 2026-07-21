import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/mistake_entry.dart';
import '../../models/question.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import 'step_solution_screen.dart';

/// Reviews one subject's outstanding mistakes — the actual questions that
/// were answered wrong, not a similar-but-different variant (that used to
/// pull a random question from the subject's whole pool, which read as
/// arbitrary/unrelated rather than an actual review of what was missed) —
/// through the same [StepSolutionScreen] used everywhere else. A mistake
/// only drops out of [AppState.mistakes] once it's been answered correctly
/// 3 times (see [AppState.recordMistakeRetry]); re-entering this screen
/// naturally resumes at whatever's still left, no separate "last position"
/// bookkeeping needed.
class MistakeReviewScreen extends StatefulWidget {
  final String subjectTitle;
  final List<MistakeEntry> mistakes;

  const MistakeReviewScreen({super.key, required this.subjectTitle, required this.mistakes});

  @override
  State<MistakeReviewScreen> createState() => _MistakeReviewScreenState();
}

class _MistakeReviewScreenState extends State<MistakeReviewScreen> {
  late Future<List<Question>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<AppState>().fetchQuestionsByIds(widget.mistakes.map((m) => m.questionId).toList());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Question>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final questions = snapshot.data ?? [];
        if (questions.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: Text('ทบทวน · ${widget.subjectTitle}')),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('ไม่พบข้อที่พลาดในวิชานี้', style: TextStyle(color: AppColors.inkFaint)),
              ),
            ),
          );
        }
        final mistakesById = {for (final m in widget.mistakes) m.questionId: m};
        final correctCounts = {for (final q in questions) q.id: mistakesById[q.id]?.correctCount ?? 0};
        return StepSolutionScreen(
          courseId: widget.mistakes.first.courseId,
          questions: questions,
          reviewTitle: widget.subjectTitle,
          correctCounts: correctCounts,
          onAnswered: (question, correct) async {
            if (!correct) return;
            final (correctCount, cleared) = await context.read<AppState>().recordMistakeRetry(question.id, true);
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  cleared ? 'เยี่ยม! ทำถูกครบ $correctCount ครั้งแล้ว ผ่านข้อนี้ 🎉' : 'ถูกต้อง! ทำถูกแล้ว $correctCount/3 ครั้ง',
                ),
                backgroundColor: cleared ? AppColors.green : null,
              ),
            );
          },
        );
      },
    );
  }
}
