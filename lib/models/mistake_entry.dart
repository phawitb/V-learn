/// One logged wrong/unsure answer, shown in Mistake Hunter grouped by
/// [unitTitle] — the subject it came from. The server derives [unitTitle]
/// from [topicTag] (which is always the owning subject's unit id), so it's
/// only ever populated on responses, never sent on create.
class MistakeEntry {
  final String questionId;
  final String topicTag;
  final String courseId;
  final String courseTitle;
  final String unitTitle;
  final String questionPrompt;

  const MistakeEntry({
    required this.questionId,
    required this.topicTag,
    required this.courseId,
    required this.courseTitle,
    this.unitTitle = '',
    required this.questionPrompt,
  });

  Map<String, dynamic> toCreateJson() => {
        'question_id': questionId,
        'topic_tag': topicTag,
        'course_id': courseId,
        'question_prompt': questionPrompt,
      };

  factory MistakeEntry.fromJson(Map<String, dynamic> json) => MistakeEntry(
        questionId: json['question_id'] as String,
        topicTag: json['topic_tag'] as String,
        courseId: json['course_id'] as String,
        courseTitle: json['course_title'] as String,
        unitTitle: json['unit_title'] as String? ?? '',
        questionPrompt: json['question_prompt'] as String,
      );
}
