import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/mock_exam.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../utils/subject_colors.dart';
import 'mock_exam_screen.dart';

/// Full-page description shown before starting a mock exam — subject
/// breakdown, total time/points, and (if the learner left one mid-way)
/// the choice to resume it or discard it and start fresh.
class MockExamIntroScreen extends StatefulWidget {
  final MockExamSet examSet;

  const MockExamIntroScreen({super.key, required this.examSet});

  @override
  State<MockExamIntroScreen> createState() => _MockExamIntroScreenState();
}

class _MockExamIntroScreenState extends State<MockExamIntroScreen> {
  late Future<MockExamStatus> _future;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _future = context.read<AppState>().mockExamStatus(widget.examSet.id);
  }

  Future<void> _begin({required bool restart}) async {
    if (restart) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('เริ่มข้อสอบใหม่?'),
          content: const Text('คำตอบที่ทำค้างไว้ในความพยายามก่อนหน้าจะถูกลบทั้งหมด'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('ยกเลิก')),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.red),
              child: const Text('เริ่มใหม่'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() => _starting = true);
    final start = await context.read<AppState>().startMockExam(widget.examSet.id, restart: restart);
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => MockExamScreen(start: start)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final set = widget.examSet;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(set.title)),
      body: _starting
          ? const Center(child: CircularProgressIndicator())
          : FutureBuilder<MockExamStatus>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final status = snapshot.data ?? const MockExamStatus(hasInProgress: false);
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(gradient: AppColors.headerGradient, borderRadius: BorderRadius.circular(20)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(set.title, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              _HeaderStat(icon: Icons.list_alt_rounded, label: '${set.totalQuestions} ข้อ'),
                              const SizedBox(width: 16),
                              _HeaderStat(icon: Icons.timer_outlined, label: '${set.durationMinutes} นาที'),
                              const SizedBox(width: 16),
                              _HeaderStat(icon: Icons.emoji_events_outlined, label: '${set.totalPoints} คะแนน'),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text('สัดส่วนข้อสอบ', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 10),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        children: [
                          _subjectRow('วิชา', 'จำนวนข้อ', 'คะแนน', header: true),
                          for (var i = 0; i < set.subjects.length; i++)
                            _subjectRow(
                              set.subjects[i].title,
                              '${set.subjects[i].count} ข้อ',
                              '${set.subjects[i].totalPoints} คะแนน',
                              color: mockExamSubjectPalette[i % mockExamSubjectPalette.length],
                            ),
                          const Divider(height: 1),
                          _subjectRow('รวม', '${set.totalQuestions} ข้อ', '${set.totalPoints} คะแนน', bold: true),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'เมื่อเริ่มแล้วเวลาจะเดินทันที ตอบได้ทุกข้อโดยไม่ต้องเรียงลำดับ และสามารถออกแล้วกลับมาทำต่อได้ภายในเวลาที่กำหนด',
                      style: TextStyle(fontSize: 12.5, color: AppColors.inkFaint, height: 1.5),
                    ),
                    const SizedBox(height: 20),
                    if (status.hasInProgress) ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.goldSoft,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.history_rounded, color: AppColors.goldInk, size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'ทำค้างไว้ ${status.answeredCount}/${status.totalQuestions} ข้อ',
                                style: const TextStyle(color: AppColors.goldInk, fontWeight: FontWeight.w700, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      ElevatedButton(onPressed: () => _begin(restart: false), child: const Text('ทำต่อ')),
                      const SizedBox(height: 8),
                      OutlinedButton(onPressed: () => _begin(restart: true), child: const Text('เริ่มใหม่')),
                    ] else
                      ElevatedButton(onPressed: () => _begin(restart: false), child: const Text('เริ่มทำข้อสอบ')),
                  ],
                );
              },
            ),
    );
  }

  Widget _subjectRow(String title, String count, String points, {bool header = false, bool bold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          if (color != null) ...[
            Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: header ? 11 : 13,
                fontWeight: header ? FontWeight.w700 : (bold ? FontWeight.w800 : FontWeight.w600),
                color: header ? AppColors.inkFaint : AppColors.ink,
              ),
            ),
          ),
          SizedBox(
            width: 72,
            child: Text(count, textAlign: TextAlign.right, style: TextStyle(fontSize: header ? 11 : 12.5, color: header ? AppColors.inkFaint : AppColors.inkSoft, fontWeight: header ? FontWeight.w700 : FontWeight.w600)),
          ),
          SizedBox(
            width: 84,
            child: Text(points, textAlign: TextAlign.right, style: TextStyle(fontSize: header ? 11 : 12.5, color: header ? AppColors.inkFaint : AppColors.inkSoft, fontWeight: header ? FontWeight.w700 : FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _HeaderStat extends StatelessWidget {
  final IconData icon;
  final String label;

  const _HeaderStat({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.white70),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

