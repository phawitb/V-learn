import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/mistake_entry.dart';
import '../../models/question.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import 'step_solution_screen.dart';

/// Reviews one subject's bookmarked questions — the actual saved questions
/// themselves (not variants, unlike [MistakeReviewScreen]), through the
/// same [StepSolutionScreen] used everywhere else. Un-bookmarking a
/// question there is what drops it out of this list on the next visit —
/// there's no separate "done reviewing" action.
class SavedQuestionReviewScreen extends StatefulWidget {
  final String subjectTitle;
  final List<MistakeEntry> saved;

  const SavedQuestionReviewScreen({super.key, required this.subjectTitle, required this.saved});

  @override
  State<SavedQuestionReviewScreen> createState() => _SavedQuestionReviewScreenState();
}

class _SavedQuestionReviewScreenState extends State<SavedQuestionReviewScreen> {
  late Future<List<Question>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<AppState>().fetchQuestionsByIds(widget.saved.map((s) => s.questionId).toList());
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
                child: Text('ไม่พบข้อที่บันทึกไว้ในวิชานี้', style: TextStyle(color: AppColors.inkFaint)),
              ),
            ),
          );
        }
        return StepSolutionScreen(
          courseId: widget.saved.first.courseId,
          questions: questions,
          reviewTitle: widget.subjectTitle,
          trackProgress: false,
        );
      },
    );
  }
}
