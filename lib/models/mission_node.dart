import 'question.dart';

/// A subject sub-course within a main course (e.g. "ภาษาไทย" inside
/// "ก.พ. ภาค ก."). Tracks its own progress independently of sibling
/// subjects — enrollment happens at the main-course level, but each
/// subject's question list is its own thing. There's no "set" grouping on
/// the path anymore: every question is directly reachable.
class MissionUnit {
  final String id;
  final String title;
  final double progress;
  final int totalQuestions;
  final DateTime? lastActivityAt;
  final List<Question> questions;

  const MissionUnit({
    required this.id,
    required this.title,
    required this.questions,
    this.progress = 0,
    this.totalQuestions = 0,
    this.lastActivityAt,
  });

  int get answeredCount => questions.where((q) => q.answered).length;

  factory MissionUnit.fromJson(Map<String, dynamic> json) => MissionUnit(
        id: json['id'] as String,
        title: json['title'] as String,
        progress: (json['progress'] as num?)?.toDouble() ?? 0,
        totalQuestions: json['total_questions'] as int? ?? 0,
        lastActivityAt:
            json['last_activity_at'] == null ? null : DateTime.parse('${json['last_activity_at']}Z').toLocal(),
        questions: (json['questions'] as List)
            .map((q) => Question.fromJson(q as Map<String, dynamic>))
            .toList(),
      );
}
