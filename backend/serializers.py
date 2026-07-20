import datetime
from typing import Optional

from sqlalchemy import func
from sqlalchemy.orm import Session

import models
import schemas

# Eggs are earned per question answered (any answer counts — "ทุกข้อคือจุด
# เรียนรู้ ไม่ใช่แค่จุดวัดผล"), now that the path has no "set" to complete.
EGGS_PER_QUESTION = 10


def record_node_answer(db: Session, user: models.User, question: models.Question, is_correct: bool) -> bool:
    """Upsert the NodeAnswer for (user, question) and award eggs the first
    time it's answered. Returns True if eggs were just awarded. Shared by
    the normal per-question answer endpoint and the daily egg challenge, so
    both feed the same progress tracking."""
    existing = (
        db.query(models.NodeAnswer)
        .filter(models.NodeAnswer.user_id == user.id, models.NodeAnswer.question_id == question.id)
        .first()
    )
    if existing is not None:
        existing.is_correct = is_correct
        db.commit()
        return False

    db.add(
        models.NodeAnswer(
            user_id=user.id,
            node_id=question.node_id,
            question_id=question.id,
            is_correct=is_correct,
        )
    )
    user.egg_balance += EGGS_PER_QUESTION
    db.commit()
    return True


def _episode_out(db: Session, user_id: int, episode: models.Episode) -> schemas.EpisodeOut:
    progress = (
        db.query(models.EpisodeProgress)
        .filter(
            models.EpisodeProgress.user_id == user_id,
            models.EpisodeProgress.episode_id == episode.id,
        )
        .first()
    )
    return schemas.EpisodeOut(
        id=episode.id,
        title=episode.title,
        duration_seconds=episode.duration_seconds,
        youtube_id=episode.youtube_id,
        completed=bool(progress and progress.completed_at is not None),
        position_seconds=progress.position_seconds if progress else 0,
    )


def question_out(db: Session, user_id: int, q: models.Question) -> schemas.QuestionOut:
    answer = (
        db.query(models.NodeAnswer)
        .filter(models.NodeAnswer.user_id == user_id, models.NodeAnswer.question_id == q.id)
        .first()
    )
    saved = (
        db.query(models.SavedQuestion)
        .filter(models.SavedQuestion.user_id == user_id, models.SavedQuestion.question_id == q.id)
        .first()
        is not None
    )
    reported = (
        db.query(models.QuestionReport)
        .filter(models.QuestionReport.user_id == user_id, models.QuestionReport.question_id == q.id)
        .first()
        is not None
    )
    return schemas.QuestionOut(
        id=q.id,
        topic_tag=q.topic_tag,
        prompt=q.prompt,
        choices=q.choices,
        correct_index=q.correct_index,
        step_solution=q.step_solution,
        answered=answer is not None,
        is_correct=bool(answer and answer.is_correct),
        saved=saved,
        reported=reported,
    )


def _mission_unit_out(db: Session, user_id: int, unit: models.MissionUnit) -> schemas.MissionUnitOut:
    questions_out = [question_out(db, user_id, q) for node in unit.nodes for q in node.questions]
    answered_count = sum(1 for q in questions_out if q.answered)
    progress = answered_count / len(questions_out) if questions_out else 0.0

    question_ids = [q.id for node in unit.nodes for q in node.questions]
    last_activity_at = None
    if question_ids:
        last_activity_at = (
            db.query(func.max(models.NodeAnswer.answered_at))
            .filter(models.NodeAnswer.user_id == user_id, models.NodeAnswer.question_id.in_(question_ids))
            .scalar()
        )

    return schemas.MissionUnitOut(
        id=unit.id,
        title=unit.title,
        progress=progress,
        total_questions=len(questions_out),
        last_activity_at=last_activity_at,
        questions=questions_out,
    )


def course_summary_out(
    db: Session, user_id: int, course: models.Course, enrollment: models.Enrollment
) -> schemas.CourseSummaryOut:
    total_episodes = sum(len(ch.episodes) for ch in course.chapters)
    completed_episodes = 0
    for ch in course.chapters:
        for ep in ch.episodes:
            progress = (
                db.query(models.EpisodeProgress)
                .filter(
                    models.EpisodeProgress.user_id == user_id,
                    models.EpisodeProgress.episode_id == ep.id,
                )
                .first()
            )
            if progress and progress.completed_at is not None:
                completed_episodes += 1
    if total_episodes:
        progress_ratio = completed_episodes / total_episodes
    else:
        # No video content (pure question-bank course): base progress on
        # how many of its questions have been answered instead.
        all_question_ids = [q.id for u in course.mission_units for n in u.nodes for q in n.questions]
        if all_question_ids:
            answered_questions = (
                db.query(models.NodeAnswer)
                .filter(
                    models.NodeAnswer.user_id == user_id,
                    models.NodeAnswer.question_id.in_(all_question_ids),
                )
                .count()
            )
            progress_ratio = answered_questions / len(all_question_ids)
        else:
            progress_ratio = 0.0

    return schemas.CourseSummaryOut(
        id=course.id,
        code=course.code,
        title=course.title,
        instructor=course.instructor,
        thumb_color_start=course.thumb_color_start,
        thumb_color_end=course.thumb_color_end,
        total_hours=course.total_hours,
        has_eggspace=course.has_eggspace,
        total_episodes=total_episodes,
        progress=progress_ratio,
        expires_at=enrollment.expires_at,
        last_episode_id=enrollment.last_episode_id,
    )


def course_catalog_out(course: models.Course, enrolled: bool) -> schemas.CourseCatalogOut:
    total_questions = sum(len(n.questions) for u in course.mission_units for n in u.nodes)
    return schemas.CourseCatalogOut(
        id=course.id,
        code=course.code,
        title=course.title,
        instructor=course.instructor,
        thumb_color_start=course.thumb_color_start,
        thumb_color_end=course.thumb_color_end,
        subject_count=len(course.mission_units),
        total_questions=total_questions,
        has_eggspace=course.has_eggspace,
        enrolled=enrolled,
    )


def course_detail_out(
    db: Session, user_id: int, course: models.Course, enrollment: models.Enrollment
) -> schemas.CourseDetailOut:
    summary = course_summary_out(db, user_id, course, enrollment)
    chapters_out = [
        schemas.ChapterOut(
            title=ch.title,
            episodes=[_episode_out(db, user_id, ep) for ep in ch.episodes],
        )
        for ch in course.chapters
    ]
    mission_units_out = [_mission_unit_out(db, user_id, u) for u in course.mission_units]
    return schemas.CourseDetailOut(
        **summary.model_dump(),
        chapters=chapters_out,
        mission_units=mission_units_out,
    )
