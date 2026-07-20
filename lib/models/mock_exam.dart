/// Per-subject breakdown of a mock exam set (question count + points),
/// shown on the full-page intro screen and used to color-code สารบัญ.
class MockExamSubject {
  final String title;
  final int count;
  final int pointsPerQuestion;
  final int totalPoints;

  const MockExamSubject({
    required this.title,
    required this.count,
    required this.pointsPerQuestion,
    required this.totalPoints,
  });

  factory MockExamSubject.fromJson(Map<String, dynamic> json) => MockExamSubject(
        title: json['title'] as String,
        count: json['count'] as int,
        pointsPerQuestion: json['points_per_question'] as int,
        totalPoints: json['total_points'] as int,
      );
}

/// One pre-generated, fixed practice exam (2 per course), sized and timed
/// to match the real exam — see backend/seed.py's EXAM_BLUEPRINTS.
class MockExamSet {
  final String id;
  final String title;
  final int durationMinutes;
  final int totalQuestions;
  final int totalPoints;
  final List<MockExamSubject> subjects;
  final bool hasInProgress;
  final DateTime? lastActivityAt;

  const MockExamSet({
    required this.id,
    required this.title,
    required this.durationMinutes,
    required this.totalQuestions,
    required this.totalPoints,
    required this.subjects,
    this.hasInProgress = false,
    this.lastActivityAt,
  });

  factory MockExamSet.fromJson(Map<String, dynamic> json) => MockExamSet(
        id: json['id'] as String,
        title: json['title'] as String,
        durationMinutes: json['duration_minutes'] as int,
        totalQuestions: json['total_questions'] as int,
        totalPoints: json['total_points'] as int,
        subjects: (json['subjects'] as List).map((s) => MockExamSubject.fromJson(s as Map<String, dynamic>)).toList(),
        hasInProgress: json['has_in_progress'] as bool? ?? false,
        lastActivityAt: json['last_activity_at'] == null ? null : DateTime.parse('${json['last_activity_at']}Z').toLocal(),
      );
}

class MockExamStatus {
  final bool hasInProgress;
  final int answeredCount;
  final int totalQuestions;

  const MockExamStatus({required this.hasInProgress, this.answeredCount = 0, this.totalQuestions = 0});

  factory MockExamStatus.fromJson(Map<String, dynamic> json) => MockExamStatus(
        hasInProgress: json['has_in_progress'] as bool,
        answeredCount: json['answered_count'] as int? ?? 0,
        totalQuestions: json['total_questions'] as int? ?? 0,
      );
}

/// A question as shown *during* an exam attempt — deliberately has no
/// correct-answer/explanation fields so the running exam can't leak them.
class ExamQuestion {
  final String id;
  final String prompt;
  final List<String> choices;
  final String subjectTitle;
  final bool saved;
  final bool reported;

  const ExamQuestion({
    required this.id,
    required this.prompt,
    required this.choices,
    required this.subjectTitle,
    this.saved = false,
    this.reported = false,
  });

  ExamQuestion copyWith({bool? saved, bool? reported}) => ExamQuestion(
        id: id,
        prompt: prompt,
        choices: choices,
        subjectTitle: subjectTitle,
        saved: saved ?? this.saved,
        reported: reported ?? this.reported,
      );

  factory ExamQuestion.fromJson(Map<String, dynamic> json) => ExamQuestion(
        id: json['id'] as String,
        prompt: json['prompt'] as String,
        choices: List<String>.from(json['choices'] as List),
        subjectTitle: json['subject_title'] as String? ?? '',
        saved: json['saved'] as bool? ?? false,
        reported: json['reported'] as bool? ?? false,
      );
}

class MockExamStart {
  final int attemptId;
  final String examSetId;
  final String title;
  final int durationMinutes;
  final DateTime startedAt;
  final Map<String, int> answers;
  final List<ExamQuestion> questions;

  const MockExamStart({
    required this.attemptId,
    required this.examSetId,
    required this.title,
    required this.durationMinutes,
    required this.startedAt,
    required this.answers,
    required this.questions,
  });

  factory MockExamStart.fromJson(Map<String, dynamic> json) => MockExamStart(
        attemptId: json['attempt_id'] as int,
        examSetId: json['exam_set_id'] as String,
        title: json['title'] as String,
        durationMinutes: json['duration_minutes'] as int,
        startedAt: DateTime.parse('${json['started_at']}Z'),
        answers: Map<String, int>.from(json['answers'] as Map),
        questions: (json['questions'] as List).map((q) => ExamQuestion.fromJson(q as Map<String, dynamic>)).toList(),
      );
}

/// One reviewed question after submission — now with the answer revealed.
class ExamReviewQuestion {
  final String id;
  final String prompt;
  final List<String> choices;
  final int correctIndex;
  final String stepSolution;
  final String subjectTitle;
  final int points;
  final int? selectedIndex;
  final bool isCorrect;
  final bool saved;
  final bool reported;

  const ExamReviewQuestion({
    required this.id,
    required this.prompt,
    required this.choices,
    required this.correctIndex,
    required this.stepSolution,
    required this.subjectTitle,
    required this.points,
    this.selectedIndex,
    required this.isCorrect,
    this.saved = false,
    this.reported = false,
  });

  factory ExamReviewQuestion.fromJson(Map<String, dynamic> json) => ExamReviewQuestion(
        id: json['id'] as String,
        prompt: json['prompt'] as String,
        choices: List<String>.from(json['choices'] as List),
        correctIndex: json['correct_index'] as int,
        stepSolution: json['step_solution'] as String,
        subjectTitle: json['subject_title'] as String? ?? '',
        points: json['points'] as int? ?? 1,
        selectedIndex: json['selected_index'] as int?,
        isCorrect: json['is_correct'] as bool,
        saved: json['saved'] as bool? ?? false,
        reported: json['reported'] as bool? ?? false,
      );
}

class MockExamResult {
  final int attemptId;
  final int score;
  final int total;
  final List<ExamReviewQuestion> questions;

  const MockExamResult({
    required this.attemptId,
    required this.score,
    required this.total,
    required this.questions,
  });

  factory MockExamResult.fromJson(Map<String, dynamic> json) => MockExamResult(
        attemptId: json['attempt_id'] as int,
        score: json['score'] as int,
        total: json['total'] as int,
        questions: (json['questions'] as List)
            .map((q) => ExamReviewQuestion.fromJson(q as Map<String, dynamic>))
            .toList(),
      );
}

/// One past, submitted exam attempt — shown in ทบทวน's history list.
class MockExamAttemptSummary {
  final int attemptId;
  final String examSetId;
  final String examSetTitle;
  final String courseId;
  final int score;
  final int total;
  final DateTime submittedAt;

  const MockExamAttemptSummary({
    required this.attemptId,
    required this.examSetId,
    required this.examSetTitle,
    required this.courseId,
    required this.score,
    required this.total,
    required this.submittedAt,
  });

  factory MockExamAttemptSummary.fromJson(Map<String, dynamic> json) => MockExamAttemptSummary(
        attemptId: json['attempt_id'] as int,
        examSetId: json['exam_set_id'] as String,
        examSetTitle: json['exam_set_title'] as String,
        courseId: json['course_id'] as String,
        score: json['score'] as int,
        total: json['total'] as int,
        submittedAt: DateTime.parse('${json['submitted_at']}Z'),
      );
}
