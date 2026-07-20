import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/mistake_entry.dart';
import '../../models/mock_exam.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../utils/relative_time.dart';
import '../exam/mock_exam_result_screen.dart';
import 'mistake_review_screen.dart';

/// ทบทวน: everything logged as wrong/unsure, grouped by subject — like the
/// คลังข้อสอบ list on Home — plus a history of past mock exam attempts,
/// viewable read-only the same way normal practice review works.
class MistakeHunterScreen extends StatefulWidget {
  const MistakeHunterScreen({super.key});

  @override
  State<MistakeHunterScreen> createState() => _MistakeHunterScreenState();
}

class _MistakeHunterScreenState extends State<MistakeHunterScreen> {
  late Future<void> _future;
  List<MockExamAttemptSummary> _attempts = [];

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<void> _load() async {
    final appState = context.read<AppState>();
    final results = await Future.wait([appState.loadMistakes(), appState.loadMockExamAttempts()]);
    _attempts = results[1] as List<MockExamAttemptSummary>;
  }

  Future<void> _reload() async {
    final result = await _load();
    if (mounted) setState(() {});
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final mistakes = context.watch<AppState>().mistakes;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('ทบทวน')),
      body: FutureBuilder<void>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (mistakes.isEmpty && _attempts.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('🎯', style: TextStyle(fontSize: 36)),
                    SizedBox(height: 12),
                    Text(
                      'ยังไม่มีข้อที่พลาดหรือไม่มั่นใจ\nทำภารกิจต่อไปเรื่อยๆ ได้เลย',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.inkFaint),
                    ),
                  ],
                ),
              ),
            );
          }

          final bySubject = <String, List<MistakeEntry>>{};
          for (final m in mistakes) {
            bySubject.putIfAbsent(m.unitTitle.isEmpty ? 'อื่นๆ' : m.unitTitle, () => []).add(m);
          }

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (bySubject.isNotEmpty) ...[
                Text('วิชาที่มีข้อพลาด (${bySubject.length})', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                for (final subject in bySubject.entries)
                  _SubjectMistakeTile(
                    title: subject.key,
                    count: subject.value.length,
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => MistakeReviewScreen(subjectTitle: subject.key, mistakes: subject.value),
                        ),
                      );
                      _reload();
                    },
                  ),
              ],
              if (_attempts.isNotEmpty) ...[
                if (bySubject.isNotEmpty) const SizedBox(height: 24),
                Text('ผลสอบเสมือนจริงที่ผ่านมา (${_attempts.length})', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                for (final attempt in _attempts)
                  _AttemptTile(
                    attempt: attempt,
                    onTap: () async {
                      final result = await context.read<AppState>().loadMockExamAttemptResult(attempt.attemptId);
                      if (!context.mounted) return;
                      await Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => MockExamResultScreen(result: result)),
                      );
                    },
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SubjectMistakeTile extends StatelessWidget {
  final String title;
  final int count;
  final VoidCallback onTap;

  const _SubjectMistakeTile({required this.title, required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: AppColors.surfaceSoft, shape: BoxShape.circle),
              child: const Text('🎯', style: TextStyle(fontSize: 15)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: AppColors.ink),
                  ),
                  const SizedBox(height: 3),
                  Text('$count ข้อที่ต้องทบทวน', style: const TextStyle(fontSize: 11, color: AppColors.inkFaint, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.inkFaint, size: 20),
          ],
        ),
      ),
    );
  }
}

class _AttemptTile extends StatelessWidget {
  final MockExamAttemptSummary attempt;
  final VoidCallback onTap;

  const _AttemptTile({required this.attempt, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final percent = attempt.total == 0 ? 0 : (attempt.score / attempt.total * 100).round();
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: AppColors.surfaceSoft, shape: BoxShape.circle),
              child: const Icon(Icons.timer_outlined, size: 16, color: AppColors.blueDark),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    attempt.examSetTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: AppColors.ink),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${attempt.score}/${attempt.total} คะแนน · ${relativeTimeLabel(attempt.submittedAt.toLocal())}',
                    style: const TextStyle(fontSize: 11, color: AppColors.inkFaint, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            Text('$percent%', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.blueDark)),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right_rounded, color: AppColors.inkFaint, size: 20),
          ],
        ),
      ),
    );
  }
}
