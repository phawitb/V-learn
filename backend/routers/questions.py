from typing import List

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

import auth
import models
import schemas
import serializers
from database import get_db

router = APIRouter(prefix="/questions", tags=["questions"])


@router.get("/by-topic", response_model=List[schemas.QuestionOut])
def questions_by_topic(
    topic_tag: str = Query(...),
    exclude: str | None = Query(default=None),
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user),
):
    q = db.query(models.Question).filter(models.Question.topic_tag == topic_tag)
    if exclude:
        q = q.filter(models.Question.id != exclude)
    rows = q.all()
    if not rows:
        rows = db.query(models.Question).filter(models.Question.topic_tag == topic_tag).all()
    return [serializers.question_out(db, current_user.id, r) for r in rows]


@router.post("/{question_id}/answer", response_model=schemas.AnswerRecordResponse)
def record_answer(
    question_id: str,
    payload: schemas.AnswerRecordRequest,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user),
):
    # The owning node comes from the question itself, not a client-supplied
    # id — Mistake Hunter replays variant questions from other nodes through
    # the same flow, so trusting the caller could misattribute progress.
    question = db.query(models.Question).filter(models.Question.id == question_id).first()
    if question is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Question not found")

    awarded = serializers.record_node_answer(db, current_user, question, payload.is_correct)
    db.refresh(current_user)
    return schemas.AnswerRecordResponse(egg_balance=current_user.egg_balance, awarded=awarded)


@router.post("/{question_id}/save", status_code=status.HTTP_204_NO_CONTENT)
def save_question(
    question_id: str,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user),
):
    question = db.query(models.Question).filter(models.Question.id == question_id).first()
    if question is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Question not found")

    existing = (
        db.query(models.SavedQuestion)
        .filter(models.SavedQuestion.user_id == current_user.id, models.SavedQuestion.question_id == question_id)
        .first()
    )
    if existing is None:
        db.add(models.SavedQuestion(user_id=current_user.id, question_id=question_id))
        db.commit()


@router.delete("/{question_id}/save", status_code=status.HTTP_204_NO_CONTENT)
def unsave_question(
    question_id: str,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user),
):
    row = (
        db.query(models.SavedQuestion)
        .filter(models.SavedQuestion.user_id == current_user.id, models.SavedQuestion.question_id == question_id)
        .first()
    )
    if row is not None:
        db.delete(row)
        db.commit()


@router.post("/{question_id}/report", status_code=status.HTTP_201_CREATED)
def report_question(
    question_id: str,
    payload: schemas.QuestionReportRequest,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user),
):
    question = db.query(models.Question).filter(models.Question.id == question_id).first()
    if question is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Question not found")

    db.add(models.QuestionReport(user_id=current_user.id, question_id=question_id, message=payload.message))
    db.commit()
    return {"status": "received"}
