import datetime
from typing import List, Optional

from pydantic import BaseModel


# ---------- Auth ----------


class GoogleAuthRequest(BaseModel):
    id_token: str


class ProfileCompleteRequest(BaseModel):
    first_name: str
    last_name: str
    phone: str


class UserOut(BaseModel):
    id: int
    email: str
    display_name: str
    first_name: Optional[str]
    last_name: Optional[str]
    phone: Optional[str]
    profile_complete: bool
    egg_balance: int
    level: int

    class Config:
        from_attributes = True


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: UserOut


# ---------- Questions ----------


class QuestionOut(BaseModel):
    id: str
    topic_tag: str
    prompt: str
    choices: List[str]
    correct_index: int
    step_solution: str
    answered: bool
    is_correct: bool
    saved: bool
    reported: bool

    class Config:
        from_attributes = True


# ---------- Episodes / Chapters ----------


class EpisodeOut(BaseModel):
    id: str
    title: str
    duration_seconds: int
    youtube_id: str
    completed: bool
    position_seconds: int


class ChapterOut(BaseModel):
    title: str
    episodes: List[EpisodeOut]


# ---------- Mission units ----------


class MissionUnitOut(BaseModel):
    id: str
    title: str
    progress: float
    total_questions: int
    last_activity_at: Optional[datetime.datetime]
    questions: List[QuestionOut]


# ---------- Courses ----------


class CourseSummaryOut(BaseModel):
    id: str
    code: str
    title: str
    instructor: str
    thumb_color_start: str
    thumb_color_end: str
    total_hours: int
    has_eggspace: bool
    total_episodes: int
    progress: float
    expires_at: datetime.datetime
    last_episode_id: Optional[str]


class CourseCatalogOut(BaseModel):
    """A main course as shown in the enroll-first catalog — no enrollment
    required to see it, so no progress/expiry fields here."""

    id: str
    code: str
    title: str
    instructor: str
    thumb_color_start: str
    thumb_color_end: str
    subject_count: int
    total_questions: int
    has_eggspace: bool
    enrolled: bool


class CourseDetailOut(CourseSummaryOut):
    chapters: List[ChapterOut]
    mission_units: List[MissionUnitOut]


# ---------- Progress ----------


class PositionUpdateRequest(BaseModel):
    position_seconds: int


class AnswerRecordRequest(BaseModel):
    is_correct: bool


class AnswerRecordResponse(BaseModel):
    egg_balance: int
    awarded: bool


class QuestionReportRequest(BaseModel):
    message: str


# ---------- Daily egg ----------


class DailyEggStatus(BaseModel):
    available: bool
    next_available_at: Optional[datetime.datetime]
    question: Optional[QuestionOut]
    level: int


class DailyEggAnswerRequest(BaseModel):
    question_id: str
    is_correct: bool


class DailyEggAnswerResponse(BaseModel):
    is_correct: bool
    egg_balance: int
    level: int
    leveled_up: bool
    next_available_at: datetime.datetime


# ---------- Mock exam ----------
# Question payloads here deliberately omit correct_index/step_solution while
# an exam is in progress — MockExamStartResponse must never leak answers.


class MockExamSubjectOut(BaseModel):
    title: str
    count: int
    points_per_question: int
    total_points: int


class MockExamSetOut(BaseModel):
    id: str
    title: str
    duration_minutes: int
    total_questions: int
    total_points: int
    subjects: List[MockExamSubjectOut]
    has_in_progress: bool = False
    last_activity_at: Optional[datetime.datetime] = None


class MockExamStatusOut(BaseModel):
    has_in_progress: bool
    answered_count: int = 0
    total_questions: int = 0


class ExamQuestionOut(BaseModel):
    id: str
    prompt: str
    choices: List[str]
    subject_title: str
    saved: bool
    reported: bool


class MockExamStartResponse(BaseModel):
    attempt_id: int
    exam_set_id: str
    title: str
    duration_minutes: int
    started_at: datetime.datetime
    answers: dict[str, int]
    questions: List[ExamQuestionOut]


class MockExamSubmitRequest(BaseModel):
    answers: dict[str, int]


class MockExamAnswerSaveRequest(BaseModel):
    question_id: str
    selected_index: Optional[int]


class ExamReviewQuestionOut(BaseModel):
    id: str
    prompt: str
    choices: List[str]
    correct_index: int
    step_solution: str
    subject_title: str
    points: int
    selected_index: Optional[int]
    is_correct: bool
    saved: bool
    reported: bool


class MockExamResultOut(BaseModel):
    attempt_id: int
    score: int
    total: int
    questions: List[ExamReviewQuestionOut]


class MockExamAttemptSummaryOut(BaseModel):
    attempt_id: int
    exam_set_id: str
    exam_set_title: str
    course_id: str
    score: int
    total: int
    submitted_at: datetime.datetime


# ---------- Mistakes ----------


class MistakeCreateRequest(BaseModel):
    question_id: str
    topic_tag: str
    course_id: str
    question_prompt: str


class MistakeOut(BaseModel):
    question_id: str
    topic_tag: str
    course_id: str
    course_title: str
    unit_title: str
    question_prompt: str


# ---------- CLEAR AI chat ----------


class ChatSendRequest(BaseModel):
    content: str


class ChatMessageOut(BaseModel):
    id: int
    role: str
    content: str
    created_at: datetime.datetime

    class Config:
        from_attributes = True


class ChatSendResponse(BaseModel):
    user_message: ChatMessageOut
    assistant_message: ChatMessageOut
