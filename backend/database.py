import os

from dotenv import load_dotenv
from pymongo import MongoClient, ReturnDocument
from pymongo.database import Database

load_dotenv()

MONGODB_URI = os.environ["MONGODB_URI"]
MONGODB_DB_NAME = os.environ.get("MONGODB_DB_NAME", "vlearn")

_client = MongoClient(MONGODB_URI)
_db = _client[MONGODB_DB_NAME]


def get_db() -> Database:
    return _db


def next_id(collection_name: str) -> int:
    """Emulates SQL autoincrement for collections that had an integer
    primary key (users, mistakes, mock_exam_attempts, ...) — keeps the JWT
    `sub` claim and every `int` id field in schemas.py unchanged."""
    doc = _db.counters.find_one_and_update(
        {"_id": collection_name},
        {"$inc": {"seq": 1}},
        upsert=True,
        return_document=ReturnDocument.AFTER,
    )
    return doc["seq"]


def next_id_batch(collection_name: str, count: int) -> list[int]:
    """Same as [next_id] but reserves `count` ids in a single round trip —
    for bulk inserts (e.g. grading all ~225 questions of a mock exam
    submission) where calling next_id() per row would be its own N+1."""
    if count <= 0:
        return []
    doc = _db.counters.find_one_and_update(
        {"_id": collection_name},
        {"$inc": {"seq": count}},
        upsert=True,
        return_document=ReturnDocument.AFTER,
    )
    last = doc["seq"]
    return list(range(last - count + 1, last + 1))


def ensure_indexes() -> None:
    """Recreates the uniqueness guarantees the old SQLAlchemy schema had via
    `UniqueConstraint`/primary keys — Mongo enforces nothing by default, so
    without these a bug could silently duplicate e.g. a user's progress row."""
    _db.users.create_index("id", unique=True)
    _db.users.create_index("email", unique=True)
    _db.users.create_index("google_sub", unique=True, sparse=True)
    for name in ("courses", "mission_units", "mission_nodes", "questions", "mock_exam_sets"):
        _db[name].create_index("id", unique=True)
    _db.enrollments.create_index(["user_id", "course_id"], unique=True)
    _db.episode_progress.create_index(["user_id", "episode_id"], unique=True)
    _db.node_answers.create_index(["user_id", "question_id"], unique=True)
    _db.mistakes.create_index(["user_id", "question_id"], unique=True)
    _db.saved_questions.create_index(["user_id", "question_id"], unique=True)
    _db.mock_exam_answers.create_index(["attempt_id", "question_id"], unique=True)

    # Non-unique lookup indexes for the FK-style queries every router does.
    _db.mission_units.create_index("course_id")
    _db.mission_nodes.create_index("unit_id")
    _db.questions.create_index("node_id")
    _db.questions.create_index("topic_tag")
    _db.chapters.create_index("course_id")
    _db.episodes.create_index("chapter_id")
    _db.enrollments.create_index("user_id")
    _db.node_answers.create_index("user_id")
    _db.mistakes.create_index("user_id")
    _db.saved_questions.create_index("user_id")
    _db.question_reports.create_index("user_id")
    _db.chat_messages.create_index("user_id")
    _db.daily_eggs.create_index("user_id")
    _db.mock_exam_sets.create_index("course_id")
    _db.mock_exam_questions.create_index("exam_set_id")
    _db.mock_exam_attempts.create_index("user_id")
    _db.mock_exam_answers.create_index("attempt_id")
