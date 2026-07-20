import datetime
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func
from sqlalchemy.orm import Session

import auth
import models
import schemas
from database import get_db

router = APIRouter(tags=["mock-exam"])


def _subjects_breakdown(exam_set: models.MockExamSet) -> List[schemas.MockExamSubjectOut]:
    by_subject: dict[str, dict] = {}
    for mq in exam_set.questions:
        entry = by_subject.setdefault(mq.subject_title, {"count": 0, "points": mq.points})
        entry["count"] += 1
    return [
        schemas.MockExamSubjectOut(
            title=title, count=data["count"], points_per_question=data["points"], total_points=data["count"] * data["points"]
        )
        for title, data in by_subject.items()
    ]


def _exam_set_out(db: Session, user_id: int, exam_set: models.MockExamSet) -> schemas.MockExamSetOut:
    subjects = _subjects_breakdown(exam_set)
    attempt = _in_progress_attempt(db, user_id, exam_set.id)
    last_activity_at = None
    if attempt is not None:
        last_activity_at = (
            db.query(func.max(models.MockExamAnswer.updated_at))
            .filter(models.MockExamAnswer.attempt_id == attempt.id)
            .scalar()
        ) or attempt.started_at
    return schemas.MockExamSetOut(
        id=exam_set.id,
        title=exam_set.title,
        duration_minutes=exam_set.duration_minutes,
        total_questions=len(exam_set.questions),
        total_points=sum(s.total_points for s in subjects),
        subjects=subjects,
        has_in_progress=attempt is not None,
        last_activity_at=last_activity_at,
    )


def _saved_reported_ids(db: Session, user_id: int, question_ids: List[str]) -> tuple[set[str], set[str]]:
    saved_ids = {
        r.question_id
        for r in db.query(models.SavedQuestion).filter(
            models.SavedQuestion.user_id == user_id, models.SavedQuestion.question_id.in_(question_ids)
        )
    }
    reported_ids = {
        r.question_id
        for r in db.query(models.QuestionReport).filter(
            models.QuestionReport.user_id == user_id, models.QuestionReport.question_id.in_(question_ids)
        )
    }
    return saved_ids, reported_ids


def _in_progress_attempt(db: Session, user_id: int, exam_set_id: str) -> Optional[models.MockExamAttempt]:
    return (
        db.query(models.MockExamAttempt)
        .filter(
            models.MockExamAttempt.user_id == user_id,
            models.MockExamAttempt.exam_set_id == exam_set_id,
            models.MockExamAttempt.submitted_at.is_(None),
        )
        .order_by(models.MockExamAttempt.started_at.desc())
        .first()
    )


@router.get("/courses/{course_id}/mock-exams", response_model=List[schemas.MockExamSetOut])
def list_mock_exams(
    course_id: str,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user),
):
    exam_sets = (
        db.query(models.MockExamSet)
        .filter(models.MockExamSet.course_id == course_id)
        .order_by(models.MockExamSet.order_index)
        .all()
    )
    return [_exam_set_out(db, current_user.id, s) for s in exam_sets]


@router.get("/mock-exams/{exam_set_id}/status", response_model=schemas.MockExamStatusOut)
def exam_status(
    exam_set_id: str,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user),
):
    attempt = _in_progress_attempt(db, current_user.id, exam_set_id)
    if attempt is None:
        return schemas.MockExamStatusOut(has_in_progress=False)
    answered_count = (
        db.query(models.MockExamAnswer)
        .filter(models.MockExamAnswer.attempt_id == attempt.id, models.MockExamAnswer.selected_index.isnot(None))
        .count()
    )
    return schemas.MockExamStatusOut(has_in_progress=True, answered_count=answered_count, total_questions=attempt.total)


@router.post("/mock-exams/{exam_set_id}/start", response_model=schemas.MockExamStartResponse)
def start_exam(
    exam_set_id: str,
    restart: bool = Query(False),
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user),
):
    exam_set = db.query(models.MockExamSet).filter(models.MockExamSet.id == exam_set_id).first()
    if exam_set is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Mock exam set not found")

    existing = _in_progress_attempt(db, current_user.id, exam_set_id)
    if existing is not None and restart:
        db.query(models.MockExamAnswer).filter(models.MockExamAnswer.attempt_id == existing.id).delete()
        db.delete(existing)
        db.commit()
        existing = None

    question_ids = [mq.question_id for mq in exam_set.questions]
    questions_by_id = {q.id: q for q in db.query(models.Question).filter(models.Question.id.in_(question_ids)).all()}
    subject_by_qid = {mq.question_id: mq.subject_title for mq in exam_set.questions}

    if existing is not None:
        attempt = existing
        saved_answers = {
            a.question_id: a.selected_index
            for a in db.query(models.MockExamAnswer).filter(models.MockExamAnswer.attempt_id == attempt.id)
            if a.selected_index is not None
        }
    else:
        attempt = models.MockExamAttempt(user_id=current_user.id, exam_set_id=exam_set.id, total=len(question_ids))
        db.add(attempt)
        db.commit()
        db.refresh(attempt)
        saved_answers = {}

    saved_ids, reported_ids = _saved_reported_ids(db, current_user.id, question_ids)

    return schemas.MockExamStartResponse(
        attempt_id=attempt.id,
        exam_set_id=exam_set.id,
        title=exam_set.title,
        duration_minutes=exam_set.duration_minutes,
        started_at=attempt.started_at,
        answers=saved_answers,
        questions=[
            schemas.ExamQuestionOut(
                id=qid,
                prompt=questions_by_id[qid].prompt,
                choices=questions_by_id[qid].choices,
                subject_title=subject_by_qid.get(qid, ""),
                saved=qid in saved_ids,
                reported=qid in reported_ids,
            )
            for qid in question_ids
            if qid in questions_by_id
        ],
    )


@router.put("/mock-exams/attempts/{attempt_id}/answer", status_code=status.HTTP_204_NO_CONTENT)
def save_answer(
    attempt_id: int,
    payload: schemas.MockExamAnswerSaveRequest,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user),
):
    attempt = (
        db.query(models.MockExamAttempt)
        .filter(models.MockExamAttempt.id == attempt_id, models.MockExamAttempt.user_id == current_user.id)
        .first()
    )
    if attempt is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Attempt not found")
    if attempt.submitted_at is not None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Attempt already submitted")

    existing = (
        db.query(models.MockExamAnswer)
        .filter(models.MockExamAnswer.attempt_id == attempt_id, models.MockExamAnswer.question_id == payload.question_id)
        .first()
    )
    if existing is not None:
        existing.selected_index = payload.selected_index
    else:
        db.add(
            models.MockExamAnswer(
                attempt_id=attempt_id, question_id=payload.question_id, selected_index=payload.selected_index
            )
        )
    db.commit()


@router.post("/mock-exams/attempts/{attempt_id}/submit", response_model=schemas.MockExamResultOut)
def submit_exam(
    attempt_id: int,
    payload: schemas.MockExamSubmitRequest,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user),
):
    attempt = (
        db.query(models.MockExamAttempt)
        .filter(models.MockExamAttempt.id == attempt_id, models.MockExamAttempt.user_id == current_user.id)
        .first()
    )
    if attempt is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Attempt not found")
    if attempt.submitted_at is not None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Attempt already submitted")

    exam_set = db.query(models.MockExamSet).filter(models.MockExamSet.id == attempt.exam_set_id).first()
    mock_questions = {mq.question_id: mq for mq in exam_set.questions}
    question_ids = list(mock_questions.keys())
    questions = {q.id: q for q in db.query(models.Question).filter(models.Question.id.in_(question_ids)).all()}
    units_by_id = {u.id: u for u in db.query(models.MissionUnit).all()}

    # Merge in any autosaved answers not present in this final payload, so a
    # resumed exam that got autosaved answers but a partial final payload
    # still grades everything that was actually selected.
    autosaved = {
        a.question_id: a.selected_index
        for a in db.query(models.MockExamAnswer).filter(models.MockExamAnswer.attempt_id == attempt.id)
    }
    answers = {**autosaved, **payload.answers}
    saved_ids, reported_ids = _saved_reported_ids(db, current_user.id, question_ids)

    score = 0
    review = []
    for qid in question_ids:
        q = questions.get(qid)
        mq = mock_questions[qid]
        if q is None:
            continue
        selected = answers.get(qid)
        is_correct = selected is not None and selected == q.correct_index
        if is_correct:
            score += mq.points
        else:
            unit = units_by_id.get(q.topic_tag)
            existing_mistake = (
                db.query(models.Mistake)
                .filter(models.Mistake.user_id == current_user.id, models.Mistake.question_id == qid)
                .first()
            )
            if existing_mistake is None:
                db.add(
                    models.Mistake(
                        user_id=current_user.id,
                        question_id=qid,
                        topic_tag=q.topic_tag,
                        course_id=unit.course_id if unit else exam_set.course_id,
                        question_prompt=q.prompt,
                    )
                )

        existing_answer = (
            db.query(models.MockExamAnswer)
            .filter(models.MockExamAnswer.attempt_id == attempt.id, models.MockExamAnswer.question_id == qid)
            .first()
        )
        if existing_answer is not None:
            existing_answer.selected_index = selected
        else:
            db.add(models.MockExamAnswer(attempt_id=attempt.id, question_id=qid, selected_index=selected))

        review.append(
            schemas.ExamReviewQuestionOut(
                id=q.id,
                prompt=q.prompt,
                choices=q.choices,
                correct_index=q.correct_index,
                step_solution=q.step_solution,
                subject_title=mq.subject_title,
                points=mq.points,
                selected_index=selected,
                is_correct=is_correct,
                saved=qid in saved_ids,
                reported=qid in reported_ids,
            )
        )

    attempt.submitted_at = datetime.datetime.utcnow()
    attempt.score = score
    db.commit()

    return schemas.MockExamResultOut(attempt_id=attempt.id, score=score, total=attempt.total, questions=review)


@router.get("/mock-exams/attempts", response_model=List[schemas.MockExamAttemptSummaryOut])
def list_attempts(
    course_id: Optional[str] = Query(None),
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user),
):
    q = (
        db.query(models.MockExamAttempt, models.MockExamSet)
        .join(models.MockExamSet, models.MockExamAttempt.exam_set_id == models.MockExamSet.id)
        .filter(models.MockExamAttempt.user_id == current_user.id, models.MockExamAttempt.submitted_at.isnot(None))
    )
    if course_id is not None:
        q = q.filter(models.MockExamSet.course_id == course_id)
    rows = q.order_by(models.MockExamAttempt.submitted_at.desc()).all()

    return [
        schemas.MockExamAttemptSummaryOut(
            attempt_id=attempt.id,
            exam_set_id=exam_set.id,
            exam_set_title=exam_set.title,
            course_id=exam_set.course_id,
            score=attempt.score or 0,
            total=attempt.total,
            submitted_at=attempt.submitted_at,
        )
        for attempt, exam_set in rows
    ]


@router.get("/mock-exams/attempts/{attempt_id}/result", response_model=schemas.MockExamResultOut)
def get_attempt_result(
    attempt_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user),
):
    attempt = (
        db.query(models.MockExamAttempt)
        .filter(models.MockExamAttempt.id == attempt_id, models.MockExamAttempt.user_id == current_user.id)
        .first()
    )
    if attempt is None or attempt.submitted_at is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Submitted attempt not found")

    exam_set = db.query(models.MockExamSet).filter(models.MockExamSet.id == attempt.exam_set_id).first()
    mock_questions = {mq.question_id: mq for mq in exam_set.questions}
    question_ids = list(mock_questions.keys())
    questions = {q.id: q for q in db.query(models.Question).filter(models.Question.id.in_(question_ids)).all()}
    answers = {
        a.question_id: a.selected_index
        for a in db.query(models.MockExamAnswer).filter(models.MockExamAnswer.attempt_id == attempt.id)
    }
    saved_ids, reported_ids = _saved_reported_ids(db, current_user.id, question_ids)

    review = []
    for qid in question_ids:
        q = questions.get(qid)
        if q is None:
            continue
        mq = mock_questions[qid]
        selected = answers.get(qid)
        review.append(
            schemas.ExamReviewQuestionOut(
                id=q.id,
                prompt=q.prompt,
                choices=q.choices,
                correct_index=q.correct_index,
                step_solution=q.step_solution,
                subject_title=mq.subject_title,
                points=mq.points,
                selected_index=selected,
                is_correct=selected is not None and selected == q.correct_index,
                saved=qid in saved_ids,
                reported=qid in reported_ids,
            )
        )

    return schemas.MockExamResultOut(attempt_id=attempt.id, score=attempt.score or 0, total=attempt.total, questions=review)
