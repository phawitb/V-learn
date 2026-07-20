import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/course.dart';
import '../../models/mission_node.dart';
import '../../models/mistake_entry.dart';
import '../../models/question.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../utils/subject_colors.dart';
import '../../widgets/egg_counter_chip.dart';
import '../../widgets/latex_text.dart';
import '../../widgets/question_circle.dart';
import '../chat/ai_chat_screen.dart';
import '../course/online_solution_screen.dart';
import 'mistake_hunter_screen.dart';

class StepSolutionResult {
  final bool allCorrect;
  const StepSolutionResult(this.allCorrect);
}

/// Step Solution exercise flow: answer → immediate detailed solution,
/// regardless of right/wrong/unsure — "ทุกข้อคือจุดเรียนรู้ ไม่ใช่แค่จุดวัดผล".
/// Wrong or "unsure" answers get logged to Mistake Hunter via the API.
///
/// This same screen also powers ทบทวน's two review flows so every question
/// display in the app looks and behaves identically:
///  - Mistake retry (ทบทวน → subject): [trackProgress] is false (variants
///    aren't real progress) and [onAnswered] clears the original mistake on
///    a correct retry.
///  - Past mock exam review: every [Question] is constructed already
///    `answered: true` with its stored [Question.selectedIndex], so choices
///    render read-only from the first frame — tapping is a no-op because
///    `_choose` already bails out once a question is answered.
/// [Question.subjectLabel], when set, overrides the unit-title pill per
/// question (used for mock exams, which span multiple subjects).
///
/// When [unit]/[course] are supplied (the main subject flow, reached
/// directly from the subject's Home tile at whatever question was left
/// off), the app bar also gets an egg counter and a shortcut menu to
/// CLEAR/Online Solution/Mistake Hunter. The สารบัญ button itself is shown
/// for any multi-question list, not just the unit-scoped one.
class StepSolutionScreen extends StatefulWidget {
  final String courseId;
  final List<Question> questions;
  final int initialIndex;
  final MissionUnit? unit;
  final Course? course;
  final String? reviewTitle;
  final bool trackProgress;
  final void Function(Question question, bool correct)? onAnswered;

  const StepSolutionScreen({
    super.key,
    required this.courseId,
    required this.questions,
    this.initialIndex = 0,
    this.unit,
    this.course,
    this.reviewTitle,
    this.trackProgress = true,
    this.onAnswered,
  });

  @override
  State<StepSolutionScreen> createState() => _StepSolutionScreenState();
}

class _StepSolutionScreenState extends State<StepSolutionScreen> {
  late int _index;
  late List<Question> _questions;
  int? _selected;
  bool _unsure = false;
  bool _answered = false;
  int _correctCount = 0;
  Timer? _ticker;
  int _elapsedSeconds = 0;

  Question get _current => _questions[_index];
  bool get _isCorrect => _selected == _current.correctIndex;

  // Mock exam review spans multiple subjects — สารบัญ colors circles by
  // subject there instead of the usual correct/wrong green/red. Normal
  // practice and mistake review only ever have one subject, so this is a
  // no-op for them (QuestionCircle falls back to its default coloring).
  List<String> get _subjectOrder => _questions.map((q) => q.subjectLabel ?? '').toList();
  bool get _hasMultipleSubjects => _subjectOrder.toSet().length > 1;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _questions = List.of(widget.questions);
    _answered = _current.answered;
    _selected = _current.selectedIndex;
    if (!_current.answered) _startTimer();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _ticker?.cancel();
    _elapsedSeconds = 0;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsedSeconds++);
    });
  }

  String get _formattedTime {
    final m = (_elapsedSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (_elapsedSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _choose(int choiceIndex) {
    if (_answered) return;
    _ticker?.cancel();
    setState(() {
      _selected = choiceIndex;
      _unsure = false;
      _answered = true;
    });
    _logIfNeeded();
  }

  void _chooseUnsure() {
    if (_answered) return;
    _ticker?.cancel();
    setState(() {
      _selected = null;
      _unsure = true;
      _answered = true;
    });
    _logIfNeeded();
  }

  void _logIfNeeded() {
    final wrongOrUnsure = _unsure || !_isCorrect;
    final correct = _isCorrect && !_unsure;
    if (correct) _correctCount++;
    if (widget.trackProgress) {
      context.read<AppState>().recordAnswer(_current.id, correct);
    }
    setState(() {
      _questions[_index] = _current.copyWith(answered: true, isCorrect: correct);
    });
    if (widget.trackProgress && wrongOrUnsure) {
      context.read<AppState>().logMistake(
            MistakeEntry(
              questionId: _current.id,
              topicTag: _current.topicTag,
              courseId: widget.courseId,
              courseTitle: '',
              questionPrompt: _current.prompt,
            ),
          );
    }
    widget.onAnswered?.call(_current, correct);
  }

  void _next() {
    if (!_answered) return;
    if (_index == _questions.length - 1) {
      Navigator.of(context).pop(StepSolutionResult(_correctCount == _questions.length));
      return;
    }
    _jumpTo(_index + 1);
  }

  void _jumpTo(int index) {
    final target = _questions[index];
    setState(() {
      _index = index;
      _selected = target.selectedIndex;
      _unsure = false;
      _answered = target.answered;
    });
    if (target.answered) {
      _ticker?.cancel();
      setState(() => _elapsedSeconds = 0);
    } else {
      _startTimer();
    }
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

  void _showQuestionPicker(BuildContext context) {
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
              Text('สารบัญ · ${widget.unit?.title ?? widget.reviewTitle ?? ''}', style: Theme.of(context).textTheme.titleMedium),
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
                      itemBuilder: (context, i) => Center(
                        child: QuestionCircle(
                          number: i + 1,
                          answered: _questions[i].answered,
                          isCorrect: _questions[i].isCorrect,
                          saved: _questions[i].saved,
                          reported: _questions[i].reported,
                          subjectColor: _hasMultipleSubjects && _questions[i].subjectLabel != null
                              ? subjectColorFor(_questions[i].subjectLabel!, _subjectOrder)
                              : null,
                          onTap: () {
                            Navigator.pop(sheetContext);
                            _jumpTo(i);
                          },
                        ),
                      ),
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

  void _showMoreMenu(BuildContext context) {
    final unit = widget.unit!;
    final course = widget.course!;
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(unit.title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    '${course.title} · ${course.remainingLabel} · หมดอายุ ${course.expiresAtLabel}',
                    style: const TextStyle(fontSize: 12, color: AppColors.inkFaint),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.lightbulb_outline, color: AppColors.red),
              title: const Text('CLEAR ถาม AI'),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AiChatScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.menu_book_outlined, color: AppColors.blueDark),
              title: const Text('Online Solution'),
              subtitle: const Text('ดูเฉลยละเอียดทุกข้อในวิชานี้'),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => OnlineSolutionScreen(course: course, unit: unit)),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.replay_circle_filled_outlined, color: AppColors.ink),
              title: const Text('Mistake Hunter'),
              subtitle: const Text('ทบทวนข้อที่พลาดหรือไม่มั่นใจ'),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const MistakeHunterScreen()),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = _current;
    final hasUnit = widget.unit != null && widget.course != null;
    final pillText = q.subjectLabel ?? widget.unit?.title ?? widget.reviewTitle;
    final showSarabun = _questions.length > 1;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('ข้อ ${_index + 1}/${_questions.length}'),
            const SizedBox(width: 8),
            _TimerBadge(time: _formattedTime),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(pillText != null ? 50 : 12),
          child: Column(
            children: [
              LinearProgressIndicator(
                value: (_index + (_answered ? 1 : 0)) / _questions.length,
                minHeight: 4,
              ),
              if (pillText != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceSoft,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    pillText,
                    style: const TextStyle(fontSize: 11, color: AppColors.inkFaint, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
        actions: [
          if (hasUnit) ...[
            Center(child: EggCounterChip(balance: context.watch<AppState>().eggBalance)),
            const SizedBox(width: 4),
          ],
          if (showSarabun)
            IconButton(
              icon: const Icon(Icons.list_alt_rounded, size: 20),
              tooltip: 'สารบัญ',
              onPressed: () => _showQuestionPicker(context),
            ),
          if (hasUnit)
            IconButton(
              icon: const Icon(Icons.more_vert_rounded, size: 20),
              onPressed: () => _showMoreMenu(context),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          LatexText(q.prompt, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: AppColors.ink, height: 1.4)),
          const SizedBox(height: 16),
          for (var i = 0; i < q.choices.length; i++) _choiceTile(i, q),
          const SizedBox(height: 6),
          if (!_answered)
            Center(
              child: TextButton.icon(
                onPressed: _chooseUnsure,
                icon: const Icon(Icons.help_outline, size: 18, color: AppColors.inkFaint),
                label: const Text('ไม่มั่นใจ', style: TextStyle(color: AppColors.inkFaint)),
              ),
            ),
          if (_answered) ...[
            const SizedBox(height: 8),
            _SolutionCard(isCorrect: _isCorrect, unsure: _unsure, question: q),
          ],
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
                onPressed: _index == 0 ? null : () => _jumpTo(_index - 1),
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
                child: ElevatedButton(
                  onPressed: _answered ? _next : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _answered ? AppColors.blueDark : AppColors.border,
                    foregroundColor: _answered ? Colors.white : AppColors.inkFaint,
                    disabledBackgroundColor: AppColors.border,
                    disabledForegroundColor: AppColors.inkFaint,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(_index == _questions.length - 1 ? 'เสร็จสิ้น' : 'ข้อถัดไป'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _choiceTile(int i, Question q) {
    Color border = AppColors.border;
    Color bg = AppColors.surface;
    Color fg = AppColors.ink;
    if (_answered) {
      if (i == q.correctIndex) {
        border = AppColors.green;
        bg = AppColors.green.withValues(alpha: 0.08);
        fg = AppColors.green;
      } else if (i == _selected) {
        border = AppColors.red;
        bg = AppColors.red.withValues(alpha: 0.08);
        fg = AppColors.red;
      }
    } else if (_selected == i) {
      border = AppColors.blueDark;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _choose(i),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border, width: _answered && (i == q.correctIndex || i == _selected) ? 1.6 : 1),
          ),
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: fg.withValues(alpha: 0.1),
                  border: Border.all(color: fg.withValues(alpha: 0.4)),
                ),
                child: Text('${i + 1}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
              ),
              const SizedBox(width: 10),
              Expanded(child: LatexText(q.choices[i], style: TextStyle(color: fg, fontSize: 14, fontWeight: FontWeight.w600))),
              if (_answered && i == q.correctIndex) const Icon(Icons.check_circle, color: AppColors.green, size: 18),
              if (_answered && i == _selected && i != q.correctIndex) const Icon(Icons.cancel, color: AppColors.red, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimerBadge extends StatelessWidget {
  final String time;

  const _TimerBadge({required this.time});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timer_outlined, size: 13, color: AppColors.inkSoft),
          const SizedBox(width: 4),
          Text(time, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.inkSoft)),
        ],
      ),
    );
  }
}

class _SolutionCard extends StatelessWidget {
  final bool isCorrect;
  final bool unsure;
  final Question question;

  const _SolutionCard({required this.isCorrect, required this.unsure, required this.question});

  @override
  Widget build(BuildContext context) {
    final label = unsure ? 'ไม่เป็นไร มาดูเฉลยกัน' : (isCorrect ? 'ตอบถูกต้อง!' : 'ยังไม่ถูก ไม่เป็นไร');
    final color = unsure ? AppColors.inkSoft : (isCorrect ? AppColors.green : AppColors.red);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(unsure ? Icons.help_rounded : (isCorrect ? Icons.check_circle : Icons.cancel), color: color, size: 18),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13.5)),
            ],
          ),
          const SizedBox(height: 10),
          const Text('Step Solution', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: AppColors.inkFaint)),
          const SizedBox(height: 6),
          LatexText(question.stepSolution, style: const TextStyle(color: AppColors.inkSoft, fontSize: 13.5, height: 1.55)),
        ],
      ),
    );
  }
}
