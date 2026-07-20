import 'package:flutter/material.dart';

import '../../models/mock_exam.dart';
import '../../models/question.dart';
import '../../theme/app_theme.dart';
import '../../utils/subject_colors.dart';
import '../eggspace/step_solution_screen.dart';

/// Score summary after a mock exam attempt (fresh submit or a past one
/// pulled from ทบทวน's history). "ดูเฉลยรายข้อ" opens the exact same
/// per-question review UI as normal practice mode, just pre-answered —
/// see [StepSolutionScreen]'s doc comment. A toggle switches that review
/// between all questions and only the ones answered wrong.
class MockExamResultScreen extends StatefulWidget {
  final MockExamResult result;

  const MockExamResultScreen({super.key, required this.result});

  @override
  State<MockExamResultScreen> createState() => _MockExamResultScreenState();
}

class _MockExamResultScreenState extends State<MockExamResultScreen> {
  bool _onlyWrong = false;

  MockExamResult get result => widget.result;

  List<Question> _buildReviewQuestions() {
    final source = _onlyWrong ? result.questions.where((q) => !q.isCorrect) : result.questions;
    return source
        .map(
          (q) => Question(
            id: q.id,
            topicTag: '',
            prompt: q.prompt,
            choices: q.choices,
            correctIndex: q.correctIndex,
            stepSolution: q.stepSolution,
            answered: true,
            isCorrect: q.isCorrect,
            saved: q.saved,
            reported: q.reported,
            selectedIndex: q.selectedIndex,
            subjectLabel: q.subjectTitle,
          ),
        )
        .toList();
  }

  List<_SubjectScore> _buildSubjectScores() {
    final order = <String>[];
    final byTitle = <String, _SubjectScore>{};
    for (final q in result.questions) {
      final entry = byTitle.putIfAbsent(q.subjectTitle, () {
        order.add(q.subjectTitle);
        return _SubjectScore(title: q.subjectTitle);
      });
      entry.totalQuestions++;
      entry.totalPoints += q.points;
      if (q.isCorrect) {
        entry.correctQuestions++;
        entry.earnedPoints += q.points;
      }
    }
    return order.map((title) => byTitle[title]!).toList();
  }

  @override
  Widget build(BuildContext context) {
    final percent = result.total == 0 ? 0.0 : result.score / result.total;
    final subjects = _buildSubjectScores();
    final wrongCount = result.questions.where((q) => !q.isCorrect).length;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('ผลสอบ'),
        automaticallyImplyLeading: false,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
            child: const Text('เสร็จสิ้น'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(gradient: AppColors.headerGradient, borderRadius: BorderRadius.circular(20)),
            child: Column(
              children: [
                const Text('คะแนนของคุณ', style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 8),
                Text('${result.score}/${result.total}', style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('${(percent * 100).round()}%', style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          if (subjects.length > 1) ...[
            const SizedBox(height: 24),
            Text('คะแนนแยกตามวิชา', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < subjects.length; i++)
                    _SubjectRow(
                      score: subjects[i],
                      color: mockExamSubjectPalette[i % mockExamSubjectPalette.length],
                      showDivider: i < subjects.length - 1,
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'แสดงเฉพาะข้อที่ทำผิด ($wrongCount ข้อ)',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink),
                      ),
                    ),
                    Switch(
                      value: _onlyWrong,
                      onChanged: wrongCount == 0 ? null : (value) => setState(() => _onlyWrong = value),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => StepSolutionScreen(
                        courseId: '',
                        questions: _buildReviewQuestions(),
                        reviewTitle: 'ผลสอบ',
                        trackProgress: false,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.fact_check_outlined, size: 18),
                label: const Text('ดูเฉลยรายข้อ'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubjectScore {
  final String title;
  int correctQuestions = 0;
  int totalQuestions = 0;
  int earnedPoints = 0;
  int totalPoints = 0;

  _SubjectScore({required this.title});
}

class _SubjectRow extends StatelessWidget {
  final _SubjectScore score;
  final Color color;
  final bool showDivider;

  const _SubjectRow({required this.score, required this.color, required this.showDivider});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  score.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink),
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'ถูก ${score.correctQuestions}/${score.totalQuestions} ข้อ',
                    style: const TextStyle(fontSize: 12, color: AppColors.inkSoft, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '${score.earnedPoints}/${score.totalPoints} คะแนน',
                    style: const TextStyle(fontSize: 11, color: AppColors.inkFaint, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (showDivider) const Divider(height: 1),
      ],
    );
  }
}
