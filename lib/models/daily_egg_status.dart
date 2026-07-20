import 'question.dart';

/// Snapshot of the "ไข่ประจำวัน" (daily egg) challenge — a single random
/// question, correct = +1 bonus egg and a level up, then a 4h cooldown
/// before the next one is issued.
class DailyEggStatus {
  final bool available;
  final DateTime? nextAvailableAt;
  final Question? question;
  final int level;

  const DailyEggStatus({
    required this.available,
    this.nextAvailableAt,
    this.question,
    required this.level,
  });

  factory DailyEggStatus.fromJson(Map<String, dynamic> json) => DailyEggStatus(
        available: json['available'] as bool,
        nextAvailableAt: json['next_available_at'] == null
            ? null
            : DateTime.parse('${json['next_available_at']}Z').toLocal(),
        question: json['question'] == null ? null : Question.fromJson(json['question'] as Map<String, dynamic>),
        level: json['level'] as int,
      );
}
