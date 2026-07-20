import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/question.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/latex_text.dart';

/// The "ไข่ประจำวัน" challenge: one random question from the course's whole
/// bank. Answer it correctly for a bonus egg and a level up; either way the
/// next one can't be claimed for another 4 hours.
class DailyEggScreen extends StatefulWidget {
  final Question question;

  const DailyEggScreen({super.key, required this.question});

  @override
  State<DailyEggScreen> createState() => _DailyEggScreenState();
}

class _DailyEggScreenState extends State<DailyEggScreen> {
  int? _selected;
  bool _answered = false;
  bool _isCorrect = false;
  bool _leveledUp = false;

  Question get _q => widget.question;

  Future<void> _choose(int choiceIndex) async {
    if (_answered) return;
    final correct = choiceIndex == _q.correctIndex;
    setState(() {
      _selected = choiceIndex;
      _answered = true;
      _isCorrect = correct;
    });
    final res = await context.read<AppState>().answerDailyEgg(_q.id, correct);
    if (!mounted) return;
    setState(() => _leveledUp = res['leveled_up'] as bool);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop(_answered)),
        title: const Text('ไข่ประจำวัน'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: AppColors.goldSoft, borderRadius: BorderRadius.circular(999)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text('🥚', style: TextStyle(fontSize: 14)),
                SizedBox(width: 6),
                Text('ตอบถูกรับไข่โบนัส + เลเวลอัพ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.goldInk)),
              ],
            ),
          ),
          const SizedBox(height: 18),
          LatexText(_q.prompt, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: AppColors.ink, height: 1.4)),
          const SizedBox(height: 16),
          for (var i = 0; i < _q.choices.length; i++) _choiceTile(i),
          if (_answered) ...[
            const SizedBox(height: 8),
            _ResultCard(isCorrect: _isCorrect, leveledUp: _leveledUp, question: _q),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('เสร็จสิ้น'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _choiceTile(int i) {
    Color border = AppColors.border;
    Color bg = AppColors.surface;
    Color fg = AppColors.ink;
    if (_answered) {
      if (i == _q.correctIndex) {
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
            border: Border.all(color: border, width: _answered && (i == _q.correctIndex || i == _selected) ? 1.6 : 1),
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
              Expanded(child: LatexText(_q.choices[i], style: TextStyle(color: fg, fontSize: 14, fontWeight: FontWeight.w600))),
              if (_answered && i == _q.correctIndex) const Icon(Icons.check_circle, color: AppColors.green, size: 18),
              if (_answered && i == _selected && i != _q.correctIndex) const Icon(Icons.cancel, color: AppColors.red, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final bool isCorrect;
  final bool leveledUp;
  final Question question;

  const _ResultCard({required this.isCorrect, required this.leveledUp, required this.question});

  @override
  Widget build(BuildContext context) {
    final label = leveledUp ? 'ถูกต้อง! ได้ 🥚 โบนัส 1 ฟอง และเลเวลอัพ!' : 'ยังไม่ถูก ลองใหม่ได้ในอีก 4 ชั่วโมง';
    final color = isCorrect ? AppColors.green : AppColors.red;
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
              Icon(isCorrect ? Icons.celebration_rounded : Icons.cancel, color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13.5))),
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
