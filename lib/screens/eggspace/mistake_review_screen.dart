import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/mistake_entry.dart';
import '../../models/question.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import 'step_solution_screen.dart';

/// Reviews one subject's outstanding mistakes with a same-topic variant
/// question per mistake — displayed through the exact same
/// [StepSolutionScreen] used by normal practice mode, so สารบัญ, the
/// bottom bar, and choice-tile styling all look and behave identically.
/// A cleared mistake drops out of [AppState.mistakes] immediately, so
/// simply re-entering this screen later naturally resumes at whatever's
/// left to review — no separate "last position" bookkeeping needed.
class MistakeReviewScreen extends StatefulWidget {
  final String subjectTitle;
  final List<MistakeEntry> mistakes;

  const MistakeReviewScreen({super.key, required this.subjectTitle, required this.mistakes});

  @override
  State<MistakeReviewScreen> createState() => _MistakeReviewScreenState();
}

class _MistakeReviewScreenState extends State<MistakeReviewScreen> {
  late Future<_LoadedVariants> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_LoadedVariants> _load() async {
    final appState = context.read<AppState>();
    final results = await Future.wait(
      widget.mistakes.map(
        (m) => appState.fetchVariantQuestions(m.topicTag, excludeQuestionId: m.questionId),
      ),
    );

    final questions = <Question>[];
    final originalIdByVariantId = <String, String>{};
    for (var i = 0; i < results.length; i++) {
      if (results[i].isEmpty) continue;
      final variant = results[i].first;
      questions.add(variant);
      originalIdByVariantId[variant.id] = widget.mistakes[i].questionId;
    }
    return _LoadedVariants(questions, originalIdByVariantId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_LoadedVariants>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final loaded = snapshot.data!;
        if (loaded.questions.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: Text('ทบทวน · ${widget.subjectTitle}')),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('ไม่พบโจทย์คล้ายกันสำหรับข้อที่พลาดในวิชานี้', style: TextStyle(color: AppColors.inkFaint)),
              ),
            ),
          );
        }
        return StepSolutionScreen(
          courseId: widget.mistakes.first.courseId,
          questions: loaded.questions,
          reviewTitle: widget.subjectTitle,
          trackProgress: false,
          onAnswered: (question, correct) {
            if (!correct) return;
            final originalId = loaded.originalIdByVariantId[question.id];
            if (originalId != null) {
              context.read<AppState>().clearMistake(originalId);
            }
          },
        );
      },
    );
  }
}

class _LoadedVariants {
  final List<Question> questions;
  final Map<String, String> originalIdByVariantId;

  const _LoadedVariants(this.questions, this.originalIdByVariantId);
}
