import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/mock_exam.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../utils/subject_colors.dart';
import '../../widgets/latex_text.dart';
import 'mock_exam_result_screen.dart';

/// A timed, real-format practice exam: every question is freely navigable
/// (no locked order, no immediate right/wrong feedback — that only shows up
/// after submitting), with a countdown that auto-submits at zero. Answers
/// autosave as the learner picks them, so leaving mid-exam and reopening
/// the same set resumes exactly where they left off (see
/// [MockExamIntroScreen]'s resume/restart choice).
class MockExamScreen extends StatefulWidget {
  final MockExamStart start;

  const MockExamScreen({super.key, required this.start});

  @override
  State<MockExamScreen> createState() => _MockExamScreenState();
}

class _MockExamScreenState extends State<MockExamScreen> {
  late List<ExamQuestion> _questions;
  late final Map<String, int> _answers;
  late final List<String> _subjectOrder;
  int _index = 0;
  Timer? _ticker;
  int _remainingSeconds = 0;
  bool _submitting = false;

  MockExamStart get _start => widget.start;

  @override
  void initState() {
    super.initState();
    _questions = List.of(_start.questions);
    _answers = Map.of(_start.answers);
    _subjectOrder = _questions.map((q) => q.subjectTitle).toList();

    final elapsed = DateTime.now().toUtc().difference(_start.startedAt).inSeconds;
    _remainingSeconds = (_start.durationMinutes * 60 - elapsed).clamp(0, _start.durationMinutes * 60);

    if (_remainingSeconds <= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _submit(auto: true));
    } else {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        if (_remainingSeconds <= 1) {
          _ticker?.cancel();
          setState(() => _remainingSeconds = 0);
          _submit(auto: true);
          return;
        }
        setState(() => _remainingSeconds--);
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String get _formattedTime {
    final h = (_remainingSeconds ~/ 3600).toString().padLeft(2, '0');
    final m = ((_remainingSeconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (_remainingSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  ExamQuestion get _current => _questions[_index];

  void _choose(int choiceIndex) {
    setState(() => _answers[_current.id] = choiceIndex);
    context.read<AppState>().saveMockExamAnswer(_start.attemptId, _current.id, choiceIndex);
  }

  Future<void> _toggleSave() async {
    final newSaved = !_current.saved;
    final appState = context.read<AppState>();
    setState(() => _questions[_index] = _current.copyWith(saved: newSaved));
    if (newSaved) {
      await appState.saveQuestion(_current.id);
    } else {
      await appState.unsaveQuestion(_current.id);
    }
  }

  Future<void> _showReportSheet(BuildContext context) async {
    final controller = TextEditingController();
    final message = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('รายงานข้อผิดพลาด', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text(
              'แจ้งปัญหาของข้อนี้ให้แอดมินตรวจสอบ เช่น โจทย์ผิด เฉลยผิด หรืออธิบายไม่ชัดเจน',
              style: TextStyle(fontSize: 12, color: AppColors.inkFaint),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              minLines: 3,
              maxLines: 5,
              decoration: InputDecoration(
                hintText: 'อธิบายปัญหาที่พบ...',
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(sheetContext, controller.text.trim()),
                child: const Text('ส่งรายงาน'),
              ),
            ),
          ],
        ),
      ),
    );
    if (message == null || message.isEmpty || !context.mounted) return;
    await context.read<AppState>().reportQuestion(_current.id, message);
    setState(() => _questions[_index] = _current.copyWith(reported: true));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ส่งรายงานแล้ว ขอบคุณครับ'), backgroundColor: AppColors.green),
      );
    }
  }

  Future<void> _submit({bool auto = false}) async {
    if (_submitting) return;
    if (!auto) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('ส่งข้อสอบ?'),
          content: Text('ทำแล้ว ${_answers.length}/${_questions.length} ข้อ ต้องการส่งข้อสอบเลยหรือไม่'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('ยกเลิก')),
            ElevatedButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('ส่งข้อสอบ')),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    _ticker?.cancel();
    setState(() => _submitting = true);
    final result = await context.read<AppState>().submitMockExam(_start.attemptId, _answers);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => MockExamResultScreen(result: result)),
    );
  }

  void _showQuestionPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollController) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('สารบัญ · ${_start.title}', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text('ทำแล้ว ${_answers.length}/${_questions.length} ข้อ', style: const TextStyle(fontSize: 12, color: AppColors.inkFaint)),
              const SizedBox(height: 14),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final crossAxisCount = (constraints.maxWidth / 58).floor().clamp(4, 10);
                    return GridView.builder(
                      controller: scrollController,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 1,
                      ),
                      itemCount: _questions.length,
                      itemBuilder: (context, i) {
                        final answered = _answers.containsKey(_questions[i].id);
                        final color = subjectColorFor(_questions[i].subjectTitle, _subjectOrder);
                        return Center(
                          child: GestureDetector(
                            onTap: () {
                              Navigator.pop(sheetContext);
                              setState(() => _index = i);
                            },
                            child: Container(
                              width: 40,
                              height: 40,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: answered ? 0.22 : 0.1),
                                shape: BoxShape.circle,
                                border: Border.all(color: color, width: answered ? 2.4 : 1.4),
                              ),
                              child: Text(
                                '${i + 1}',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color),
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_submitting) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final q = _current;
    final selected = _answers[q.id];
    final lowTime = _remainingSeconds < 300;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('ออกจากข้อสอบ?'),
            content: const Text('คำตอบที่ทำไว้ถูกบันทึกอัตโนมัติแล้ว กลับมาทำต่อได้ภายในเวลาที่กำหนด'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('อยู่ต่อ')),
              TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('ออก')),
            ],
          ),
        );
        if (leave == true && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text('ข้อ ${_index + 1}/${_questions.length}'),
          actions: [
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: lowTime ? AppColors.red.withValues(alpha: 0.1) : AppColors.surfaceSoft,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: lowTime ? AppColors.red : AppColors.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.timer_outlined, size: 13, color: lowTime ? AppColors.red : AppColors.inkSoft),
                    const SizedBox(width: 4),
                    Text(_formattedTime, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: lowTime ? AppColors.red : AppColors.inkSoft)),
                  ],
                ),
              ),
            ),
            IconButton(icon: const Icon(Icons.list_alt_rounded, size: 20), tooltip: 'สารบัญ', onPressed: _showQuestionPicker),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(4),
            child: LinearProgressIndicator(value: _answers.length / _questions.length, minHeight: 4),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
          children: [
            Text(
              q.subjectTitle,
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: subjectColorFor(q.subjectTitle, _subjectOrder)),
            ),
            const SizedBox(height: 4),
            LatexText(q.prompt, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: AppColors.ink, height: 1.4)),
            const SizedBox(height: 16),
            for (var i = 0; i < q.choices.length; i++) _choiceTile(q, i, selected),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 16, 10),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 17),
                  tooltip: 'ข้อก่อนหน้า',
                  color: AppColors.inkFaint,
                  onPressed: _index == 0 ? null : () => setState(() => _index--),
                ),
                IconButton(
                  icon: Icon(
                    q.saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                    color: q.saved ? AppColors.gold : AppColors.inkFaint,
                  ),
                  tooltip: 'บันทึกข้อนี้',
                  onPressed: _toggleSave,
                ),
                IconButton(
                  icon: const Icon(Icons.flag_outlined),
                  color: AppColors.inkFaint,
                  tooltip: 'รายงานข้อผิดพลาด',
                  onPressed: () => _showReportSheet(context),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _index == _questions.length - 1
                      ? ElevatedButton(
                          onPressed: () => _submit(),
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.red),
                          child: const Text('ส่งข้อสอบ'),
                        )
                      : ElevatedButton(
                          onPressed: () => setState(() => _index++),
                          child: const Text('ข้อถัดไป'),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _choiceTile(ExamQuestion q, int i, int? selected) {
    final isSelected = selected == i;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _choose(i),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.blueDark.withValues(alpha: 0.08) : AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isSelected ? AppColors.blueDark : AppColors.border, width: isSelected ? 1.6 : 1),
          ),
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected ? AppColors.blueDark.withValues(alpha: 0.15) : AppColors.ink.withValues(alpha: 0.1),
                  border: Border.all(color: isSelected ? AppColors.blueDark : AppColors.ink.withValues(alpha: 0.4)),
                ),
                child: Text(
                  '${i + 1}',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: isSelected ? AppColors.blueDark : AppColors.ink),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: LatexText(
                  q.choices[i],
                  style: TextStyle(color: isSelected ? AppColors.blueDark : AppColors.ink, fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
