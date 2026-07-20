/// A single exercise question used by both mission nodes and Mistake Hunter
/// variant practice. [topicTag] links wrong/unsure answers back to a pool of
/// similar-but-not-identical questions, mirroring eggspace's "Mistake Hunter".
/// [answered]/[isCorrect]/[saved]/[reported] are the signed-in user's own
/// history with this question — the server is the source of truth for all.
class Question {
  final String id;
  final String topicTag;
  final String prompt;
  final List<String> choices;
  final int correctIndex;
  final String stepSolution;
  final bool answered;
  final bool isCorrect;
  final bool saved;
  final bool reported;
  final int? selectedIndex;
  final String? subjectLabel;

  const Question({
    required this.id,
    required this.topicTag,
    required this.prompt,
    required this.choices,
    required this.correctIndex,
    required this.stepSolution,
    this.answered = false,
    this.isCorrect = false,
    this.saved = false,
    this.reported = false,
    this.selectedIndex,
    this.subjectLabel,
  });

  Question copyWith({bool? answered, bool? isCorrect, bool? saved, bool? reported}) => Question(
        id: id,
        topicTag: topicTag,
        prompt: prompt,
        choices: choices,
        correctIndex: correctIndex,
        stepSolution: stepSolution,
        answered: answered ?? this.answered,
        isCorrect: isCorrect ?? this.isCorrect,
        saved: saved ?? this.saved,
        reported: reported ?? this.reported,
        selectedIndex: selectedIndex,
        subjectLabel: subjectLabel,
      );

  factory Question.fromJson(Map<String, dynamic> json) => Question(
        id: json['id'] as String,
        topicTag: json['topic_tag'] as String,
        prompt: json['prompt'] as String,
        choices: List<String>.from(json['choices'] as List),
        correctIndex: json['correct_index'] as int,
        stepSolution: json['step_solution'] as String,
        answered: json['answered'] as bool? ?? false,
        isCorrect: json['is_correct'] as bool? ?? false,
        saved: json['saved'] as bool? ?? false,
        reported: json['reported'] as bool? ?? false,
      );
}
