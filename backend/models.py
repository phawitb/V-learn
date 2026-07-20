import datetime

from sqlalchemy import (
    Boolean,
    Column,
    DateTime,
    ForeignKey,
    Integer,
    JSON,
    String,
    UniqueConstraint,
)
from sqlalchemy.orm import relationship

from database import Base


def utcnow():
    return datetime.datetime.utcnow()


class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    email = Column(String, unique=True, index=True, nullable=False)
    google_sub = Column(String, unique=True, index=True, nullable=True)
    first_name = Column(String, nullable=True)
    last_name = Column(String, nullable=True)
    phone = Column(String, nullable=True)
    display_name = Column(String, nullable=False)
    egg_balance = Column(Integer, nullable=False, default=100)
    level = Column(Integer, nullable=False, default=1)
    created_at = Column(DateTime, default=utcnow)

    enrollments = relationship("Enrollment", back_populates="user")

    @property
    def profile_complete(self) -> bool:
        return bool(self.first_name and self.last_name and self.phone)


class Course(Base):
    __tablename__ = "courses"

    id = Column(String, primary_key=True)
    code = Column(String, nullable=False)
    title = Column(String, nullable=False)
    instructor = Column(String, nullable=False)
    thumb_color_start = Column(String, nullable=False)
    thumb_color_end = Column(String, nullable=False)
    total_hours = Column(Integer, nullable=False)
    has_eggspace = Column(Boolean, nullable=False, default=False)
    order_index = Column(Integer, nullable=False, default=0)

    chapters = relationship(
        "Chapter", back_populates="course", order_by="Chapter.order_index"
    )
    mission_units = relationship(
        "MissionUnit", back_populates="course", order_by="MissionUnit.order_index"
    )


class Chapter(Base):
    __tablename__ = "chapters"

    id = Column(Integer, primary_key=True, autoincrement=True)
    course_id = Column(String, ForeignKey("courses.id"), nullable=False)
    title = Column(String, nullable=False)
    order_index = Column(Integer, nullable=False, default=0)

    course = relationship("Course", back_populates="chapters")
    episodes = relationship(
        "Episode", back_populates="chapter", order_by="Episode.order_index"
    )


class Episode(Base):
    __tablename__ = "episodes"

    id = Column(String, primary_key=True)
    chapter_id = Column(Integer, ForeignKey("chapters.id"), nullable=False)
    title = Column(String, nullable=False)
    duration_seconds = Column(Integer, nullable=False)
    youtube_id = Column(String, nullable=False)
    order_index = Column(Integer, nullable=False, default=0)

    chapter = relationship("Chapter", back_populates="episodes")


class MissionUnit(Base):
    __tablename__ = "mission_units"

    id = Column(String, primary_key=True)
    course_id = Column(String, ForeignKey("courses.id"), nullable=False)
    title = Column(String, nullable=False)
    order_index = Column(Integer, nullable=False, default=0)

    course = relationship("Course", back_populates="mission_units")
    nodes = relationship(
        "MissionNode", back_populates="unit", order_by="MissionNode.order_index"
    )


class MissionNode(Base):
    __tablename__ = "mission_nodes"

    id = Column(String, primary_key=True)
    unit_id = Column(String, ForeignKey("mission_units.id"), nullable=False)
    title = Column(String, nullable=False)
    type = Column(String, nullable=False)  # lesson | exercise | special
    lesson_count = Column(Integer, nullable=False, default=0)
    exercise_count = Column(Integer, nullable=False, default=0)
    youtube_id = Column(String, nullable=True)
    egg_reward = Column(Integer, nullable=False, default=20)
    order_index = Column(Integer, nullable=False, default=0)

    unit = relationship("MissionUnit", back_populates="nodes")
    questions = relationship(
        "Question", back_populates="node", order_by="Question.order_index"
    )


class Question(Base):
    __tablename__ = "questions"

    id = Column(String, primary_key=True)
    node_id = Column(String, ForeignKey("mission_nodes.id"), nullable=False)
    topic_tag = Column(String, nullable=False, index=True)
    prompt = Column(String, nullable=False)
    choices = Column(JSON, nullable=False)
    correct_index = Column(Integer, nullable=False)
    step_solution = Column(String, nullable=False)
    order_index = Column(Integer, nullable=False, default=0)

    node = relationship("MissionNode", back_populates="questions")


class Enrollment(Base):
    __tablename__ = "enrollments"
    __table_args__ = (UniqueConstraint("user_id", "course_id"),)

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    course_id = Column(String, ForeignKey("courses.id"), nullable=False)
    purchased_at = Column(DateTime, default=utcnow)
    expires_at = Column(DateTime, nullable=False)
    last_episode_id = Column(String, nullable=True)

    user = relationship("User", back_populates="enrollments")


class EpisodeProgress(Base):
    __tablename__ = "episode_progress"
    __table_args__ = (UniqueConstraint("user_id", "episode_id"),)

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    episode_id = Column(String, ForeignKey("episodes.id"), nullable=False)
    position_seconds = Column(Integer, nullable=False, default=0)
    completed_at = Column(DateTime, nullable=True)
    updated_at = Column(DateTime, default=utcnow, onupdate=utcnow)


class NodeAnswer(Base):
    """One question a user has answered, regardless of correctness — the
    unit of progress and egg-earning now that the path is per-question
    instead of grouped into sets."""

    __tablename__ = "node_answers"
    __table_args__ = (UniqueConstraint("user_id", "question_id"),)

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    node_id = Column(String, ForeignKey("mission_nodes.id"), nullable=False)
    question_id = Column(String, ForeignKey("questions.id"), nullable=False)
    is_correct = Column(Boolean, nullable=False)
    answered_at = Column(DateTime, default=utcnow)


class Mistake(Base):
    __tablename__ = "mistakes"
    __table_args__ = (UniqueConstraint("user_id", "question_id"),)

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    question_id = Column(String, nullable=False)
    topic_tag = Column(String, nullable=False)
    course_id = Column(String, ForeignKey("courses.id"), nullable=False)
    question_prompt = Column(String, nullable=False)
    created_at = Column(DateTime, default=utcnow)


class ChatMessage(Base):
    """One turn in the CLEAR AI chat. `role` is "user" or "assistant"."""

    __tablename__ = "chat_messages"

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    role = Column(String, nullable=False)
    content = Column(String, nullable=False)
    created_at = Column(DateTime, default=utcnow)


class SavedQuestion(Base):
    __tablename__ = "saved_questions"
    __table_args__ = (UniqueConstraint("user_id", "question_id"),)

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    question_id = Column(String, ForeignKey("questions.id"), nullable=False)
    saved_at = Column(DateTime, default=utcnow)


class QuestionReport(Base):
    __tablename__ = "question_reports"

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    question_id = Column(String, ForeignKey("questions.id"), nullable=False)
    message = Column(String, nullable=False)
    created_at = Column(DateTime, default=utcnow)


class DailyEgg(Base):
    """One random-question egg challenge. `answered_at` is null while it's
    still pending; once answered, the next one can't be issued until 4h
    later regardless of whether it was answered correctly."""

    __tablename__ = "daily_eggs"

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    question_id = Column(String, ForeignKey("questions.id"), nullable=False)
    issued_at = Column(DateTime, default=utcnow)
    answered_at = Column(DateTime, nullable=True)
    is_correct = Column(Boolean, nullable=True)


class MockExamSet(Base):
    """A fixed, pre-generated practice exam — 2 per course, sized and timed
    to match the real exam (see seed.py's EXAM_BLUEPRINTS)."""

    __tablename__ = "mock_exam_sets"

    id = Column(String, primary_key=True)
    course_id = Column(String, ForeignKey("courses.id"), nullable=False)
    title = Column(String, nullable=False)
    order_index = Column(Integer, nullable=False, default=0)
    duration_minutes = Column(Integer, nullable=False)

    questions = relationship(
        "MockExamQuestion", back_populates="exam_set", order_by="MockExamQuestion.order_index"
    )


class MockExamQuestion(Base):
    __tablename__ = "mock_exam_questions"

    id = Column(Integer, primary_key=True, autoincrement=True)
    exam_set_id = Column(String, ForeignKey("mock_exam_sets.id"), nullable=False)
    question_id = Column(String, ForeignKey("questions.id"), nullable=False)
    subject_title = Column(String, nullable=False)
    points = Column(Integer, nullable=False, default=1)
    order_index = Column(Integer, nullable=False, default=0)

    exam_set = relationship("MockExamSet", back_populates="questions")


class MockExamAttempt(Base):
    __tablename__ = "mock_exam_attempts"

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    exam_set_id = Column(String, ForeignKey("mock_exam_sets.id"), nullable=False)
    started_at = Column(DateTime, default=utcnow)
    submitted_at = Column(DateTime, nullable=True)
    score = Column(Integer, nullable=True)
    total = Column(Integer, nullable=False)


class MockExamAnswer(Base):
    __tablename__ = "mock_exam_answers"
    __table_args__ = (UniqueConstraint("attempt_id", "question_id"),)

    id = Column(Integer, primary_key=True, autoincrement=True)
    attempt_id = Column(Integer, ForeignKey("mock_exam_attempts.id"), nullable=False)
    question_id = Column(String, ForeignKey("questions.id"), nullable=False)
    selected_index = Column(Integer, nullable=True)
    updated_at = Column(DateTime, default=utcnow, onupdate=utcnow)
