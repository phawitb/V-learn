import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/daily_egg_status.dart';
import '../screens/eggspace/daily_egg_screen.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

/// Home-screen banner for the "ไข่ประจำวัน" challenge: a claim button when a
/// random question is ready, otherwise a live countdown to the next one.
class DailyEggCard extends StatefulWidget {
  final String courseId;

  const DailyEggCard({super.key, required this.courseId});

  @override
  State<DailyEggCard> createState() => _DailyEggCardState();
}

class _DailyEggCardState extends State<DailyEggCard> {
  DailyEggStatus? _status;
  Timer? _ticker;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final status = await context.read<AppState>().loadDailyEggStatus(widget.courseId);
    if (!mounted) return;
    setState(() => _status = status);
    _ticker?.cancel();
    if (!status.available && status.nextAvailableAt != null) {
      _tick();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    }
  }

  void _tick() {
    final next = _status?.nextAvailableAt;
    if (next == null) return;
    final remaining = next.difference(DateTime.now());
    if (remaining.isNegative) {
      _ticker?.cancel();
      _load();
      return;
    }
    if (mounted) setState(() => _remaining = remaining);
  }

  Future<void> _claim() async {
    final status = _status;
    if (status == null || status.question == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DailyEggScreen(question: status.question!)),
    );
    _load();
  }

  String _formatDuration(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final level = status?.level ?? context.watch<AppState>().currentUser?.level ?? 1;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [AppColors.gold, Color(0xFFE8A93A)]),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const Text('🥚', style: TextStyle(fontSize: 30)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ไข่ประจำวัน · เลเวล $level', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13.5)),
                const SizedBox(height: 3),
                Text(
                  status == null
                      ? 'กำลังโหลด...'
                      : status.available
                          ? 'ตอบถูก 1 ข้อ รับไข่โบนัส + เลเวลอัพ'
                          : 'เก็บครั้งถัดไปอีก ${_formatDuration(_remaining)}',
                  style: const TextStyle(color: Colors.white, fontSize: 11.5),
                ),
              ],
            ),
          ),
          if (status?.available == true)
            OutlinedButton(
              onPressed: _claim,
              style: OutlinedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.goldInk,
                side: BorderSide.none,
              ),
              child: const Text('เก็บไข่'),
            ),
        ],
      ),
    );
  }
}
