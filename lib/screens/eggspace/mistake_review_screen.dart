import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/mistake_entry.dart';
import '../../models/question.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import 'step_solution_screen.dart';

/// Reviews one subject's outstanding mistakes with a same-topic variant
/// question per mistake, freshly randomized every time this screen opens
/// (so it never quietly reuses the exact same variant a learner already
/// answered last visit) — displayed through the exact same
/// [StepSolutionScreen] used by normal practice mode, so สารบัญ, the
/// bottom bar, and choice-tile styling all look and behave identically.
/// A mistake only drops out of [AppState.mistakes] once its variant has
/// been answered correctly 3 times (see [AppState.recordMistakeRetry]) —
/// re-entering this screen naturally resumes at whatever's still left,
/// no separate "last position" bookkeeping needed.
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
    // topic_tag is subject-wide (every mistake in this subject shares the
    // same value), so fetching it separately per mistake — as this used to —
    // returned the same overlapping pool every time. Fetch the pool once,
    // shuffle it, and hand out a distinct question per mistake instead —
    // shuffling (not just de-duplicating) is what makes each visit show a
    // genuinely different variant instead of the same deterministic pick.
    final pool = List<Question>.of(await appState.fetchVariantQuestions(widget.mistakes.first.topicTag))..shuffle(Random());

    final assigned = <String>{};
    final questions = <Question>[];
    final originalIdByVariantId = <String, String>{};
    for (final mistake in widget.mistakes) {
      if (pool.isEmpty) continue;
      // Prefer a question that's neither the mistake's own original nor
      // already handed to an earlier mistake in this batch; fall back to
      // just "not the original" (a repeat across mistakes, but never the
      // exact question just missed) if the subject's pool is that small.
      final candidate = pool.firstWhere(
        (q) => q.id != mistake.questionId && !assigned.contains(q.id),
        orElse: () => pool.firstWhere((q) => q.id != mistake.questionId, orElse: () => pool.first),
      );
      assigned.add(candidate.id);
      questions.add(candidate);
      originalIdByVariantId[candidate.id] = mistake.questionId;
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
          onAnswered: (question, correct) async {
            if (!correct) return;
            final originalId = loaded.originalIdByVariantId[question.id];
            if (originalId == null) return;
            final (correctCount, cleared) = await context.read<AppState>().recordMistakeRetry(originalId, true);
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

class _LoadedVariants {
  final List<Question> questions;
  final Map<String, String> originalIdByVariantId;

  const _LoadedVariants(this.questions, this.originalIdByVariantId);
}
