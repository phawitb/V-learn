import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_message.dart';
import '../models/course.dart';
import '../models/course_catalog_entry.dart';
import '../models/daily_egg_status.dart';
import '../models/mistake_entry.dart';
import '../models/mock_exam.dart';
import '../models/question.dart';
import '../models/user.dart';
import '../services/api_client.dart';
import '../services/google_auth_service.dart';

/// Central app state: auth session, course list, egg balance, mistake log
/// and the CLEAR AI chat — all backed by the FastAPI service in `backend/`.
/// Only the JWT is persisted locally (shared_preferences); everything else
/// is fetched fresh from the API so the server stays the source of truth.
class AppState extends ChangeNotifier {
  AppState(this._prefs);

  final SharedPreferences _prefs;
  final ApiClient _api = ApiClient.instance;

  static const _kToken = 'auth_token';
  static const _kActiveCourse = 'active_course_id';

  AppUser? currentUser;
  List<Course> courses = [];
  List<MistakeEntry> mistakes = [];
  List<ChatMessage> chatMessages = [];
  bool isInitializing = true;

  bool get isAuthenticated => currentUser != null;
  int get eggBalance => currentUser?.eggBalance ?? 0;

  Future<void> init() async {
    final token = _prefs.getString(_kToken);
    if (token != null) {
      _api.token = token;
      try {
        currentUser = AppUser.fromJson(await _api.get('/auth/me'));
      } catch (_) {
        await _clearSession();
      }
    }
    isInitializing = false;
    notifyListeners();
  }

  Future<void> _saveSession(String token, AppUser user) async {
    _api.token = token;
    currentUser = user;
    await _prefs.setString(_kToken, token);
    notifyListeners();
  }

  Future<void> _clearSession() async {
    _api.token = null;
    currentUser = null;
    courses = [];
    mistakes = [];
    chatMessages = [];
    await _prefs.remove(_kToken);
  }

  Future<void> signInWithGoogle(String idToken) async {
    final res = await _api.post('/auth/google', body: {'id_token': idToken});
    await _saveSession(res['access_token'] as String, AppUser.fromJson(res['user']));
  }

  Future<void> completeProfile({
    required String firstName,
    required String lastName,
    required String phone,
  }) async {
    final res = await _api.post('/auth/profile', body: {
      'first_name': firstName,
      'last_name': lastName,
      'phone': phone,
    });
    currentUser = AppUser.fromJson(res as Map<String, dynamic>);
    notifyListeners();
  }

  Future<void> logout() async {
    await _clearSession();
    await GoogleAuthService.instance.signOut();
    notifyListeners();
  }

  // ---------------- Courses ----------------

  Future<List<Course>> loadCourses() async {
    final res = await _api.get('/courses') as List;
    courses = res.map((c) => Course.fromJson(c as Map<String, dynamic>)).toList();
    notifyListeners();
    return courses;
  }

  Future<Course> loadCourseDetail(String courseId) async {
    final res = await _api.get('/courses/$courseId');
    return Course.fromJson(res as Map<String, dynamic>);
  }

  Future<List<CourseCatalogEntry>> loadCatalog() async {
    final res = await _api.get('/courses/catalog') as List;
    return res.map((c) => CourseCatalogEntry.fromJson(c as Map<String, dynamic>)).toList();
  }

  Future<void> enrollInCourse(String courseId) async {
    await _api.post('/courses/$courseId/enroll');
  }

  // DEV ONLY: this app currently ships as a single-course build, but which
  // course is picked at runtime via the settings sheet on the home screen
  // instead of a compile-time constant. Remove `activeCourseId`/
  // `setActiveCourseId` and the settings sheet before a real per-course
  // production deploy, where the course should just be hardcoded.
  String? get activeCourseId => _prefs.getString(_kActiveCourse);

  Future<void> setActiveCourseId(String id) async {
    await _prefs.setString(_kActiveCourse, id);
    notifyListeners();
  }

  // ---------------- Episodes ----------------

  Future<void> setEpisodePosition(String episodeId, int seconds) async {
    try {
      await _api.post('/episodes/$episodeId/progress', body: {'position_seconds': seconds});
    } catch (_) {
      // Best-effort; a dropped position update isn't worth surfacing to the UI.
    }
  }

  Future<void> markEpisodeCompleted(String episodeId) async {
    await _api.post('/episodes/$episodeId/complete');
  }

  // ---------------- eggspace missions ----------------

  /// Records an answer (right or wrong — every question is a learning
  /// point) and awards eggs the first time this question is answered.
  /// Returns true if eggs were just awarded, so the caller can decide
  /// whether to show a reward cue.
  Future<bool> recordAnswer(String questionId, bool isCorrect) async {
    try {
      final res = await _api.post('/questions/$questionId/answer', body: {'is_correct': isCorrect});
      final newBalance = res['egg_balance'] as int;
      final awarded = res['awarded'] as bool;
      if (currentUser != null) {
        currentUser = currentUser!.copyWith(eggBalance: newBalance);
        notifyListeners();
      }
      return awarded;
    } catch (_) {
      // Best-effort; a dropped progress ping isn't worth surfacing to the UI.
      return false;
    }
  }

  Future<void> saveQuestion(String questionId) async {
    await _api.post('/questions/$questionId/save');
  }

  Future<void> unsaveQuestion(String questionId) async {
    await _api.delete('/questions/$questionId/save');
  }

  Future<void> reportQuestion(String questionId, String message) async {
    await _api.post('/questions/$questionId/report', body: {'message': message});
  }

  Future<List<Question>> fetchVariantQuestions(String topicTag, {String? excludeQuestionId}) async {
    final query = excludeQuestionId == null
        ? '/questions/by-topic?topic_tag=$topicTag'
        : '/questions/by-topic?topic_tag=$topicTag&exclude=$excludeQuestionId';
    final res = await _api.get(query) as List;
    return res.map((q) => Question.fromJson(q as Map<String, dynamic>)).toList();
  }

  // ---------------- Mistake Hunter ----------------

  Future<void> loadMistakes() async {
    final res = await _api.get('/mistakes') as List;
    mistakes = res.map((m) => MistakeEntry.fromJson(m as Map<String, dynamic>)).toList();
    notifyListeners();
  }

  Future<void> logMistake(MistakeEntry entry) async {
    final res = await _api.post('/mistakes', body: entry.toCreateJson());
    final saved = MistakeEntry.fromJson(res as Map<String, dynamic>);
    if (!mistakes.any((m) => m.questionId == saved.questionId)) {
      mistakes.add(saved);
      notifyListeners();
    }
  }

  Future<void> clearMistake(String questionId) async {
    await _api.delete('/mistakes/$questionId');
    mistakes.removeWhere((m) => m.questionId == questionId);
    notifyListeners();
  }

  // ---------------- Daily egg ----------------

  Future<DailyEggStatus> loadDailyEggStatus(String courseId) async {
    final res = await _api.get('/eggs/daily?course_id=$courseId') as Map<String, dynamic>;
    final status = DailyEggStatus.fromJson(res);
    if (currentUser != null && currentUser!.level != status.level) {
      currentUser = currentUser!.copyWith(level: status.level);
      notifyListeners();
    }
    return status;
  }

  Future<Map<String, dynamic>> answerDailyEgg(String questionId, bool isCorrect) async {
    final res = await _api.post('/eggs/daily/answer', body: {
      'question_id': questionId,
      'is_correct': isCorrect,
    }) as Map<String, dynamic>;
    if (currentUser != null) {
      currentUser = currentUser!.copyWith(
        eggBalance: res['egg_balance'] as int,
        level: res['level'] as int,
      );
      notifyListeners();
    }
    return res;
  }

  // ---------------- Mock exam ----------------

  Future<List<MockExamSet>> loadMockExams(String courseId) async {
    final res = await _api.get('/courses/$courseId/mock-exams') as List;
    return res.map((e) => MockExamSet.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<MockExamStatus> mockExamStatus(String examSetId) async {
    final res = await _api.get('/mock-exams/$examSetId/status') as Map<String, dynamic>;
    return MockExamStatus.fromJson(res);
  }

  Future<MockExamStart> startMockExam(String examSetId, {bool restart = false}) async {
    final res = await _api.post('/mock-exams/$examSetId/start${restart ? '?restart=true' : ''}') as Map<String, dynamic>;
    return MockExamStart.fromJson(res);
  }

  Future<void> saveMockExamAnswer(int attemptId, String questionId, int? selectedIndex) async {
    try {
      await _api.put('/mock-exams/attempts/$attemptId/answer', body: {
        'question_id': questionId,
        'selected_index': selectedIndex,
      });
    } catch (_) {
      // Best-effort autosave; the final submit payload is the source of truth.
    }
  }

  Future<MockExamResult> submitMockExam(int attemptId, Map<String, int> answers) async {
    final res = await _api.post('/mock-exams/attempts/$attemptId/submit', body: {'answers': answers}) as Map<String, dynamic>;
    return MockExamResult.fromJson(res);
  }

  Future<List<MockExamAttemptSummary>> loadMockExamAttempts({String? courseId}) async {
    final query = courseId == null ? '' : '?course_id=$courseId';
    final res = await _api.get('/mock-exams/attempts$query') as List;
    return res.map((e) => MockExamAttemptSummary.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<MockExamResult> loadMockExamAttemptResult(int attemptId) async {
    final res = await _api.get('/mock-exams/attempts/$attemptId/result') as Map<String, dynamic>;
    return MockExamResult.fromJson(res);
  }

  // ---------------- CLEAR AI chat ----------------

  Future<void> loadChatMessages() async {
    final res = await _api.get('/chat') as List;
    chatMessages = res.map((m) => ChatMessage.fromJson(m as Map<String, dynamic>)).toList();
    notifyListeners();
  }

  Future<void> sendChatMessage(String content) async {
    final res = await _api.post('/chat', body: {'content': content}) as Map<String, dynamic>;
    chatMessages.add(ChatMessage.fromJson(res['user_message'] as Map<String, dynamic>));
    chatMessages.add(ChatMessage.fromJson(res['assistant_message'] as Map<String, dynamic>));
    notifyListeners();
  }
}
