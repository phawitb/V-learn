import datetime
import random

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

import auth
import models
import schemas
import serializers
from database import get_db

router = APIRouter(prefix="/eggs/daily", tags=["daily-egg"])

COOLDOWN = datetime.timedelta(hours=4)
BONUS_EGGS = 1


def _random_question(db: Session, course_id: str) -> models.Question | None:
    questions = (
        db.query(models.Question)
        .join(models.MissionNode, models.Question.node_id == models.MissionNode.id)
        .join(models.MissionUnit, models.MissionNode.unit_id == models.MissionUnit.id)
        .filter(models.MissionUnit.course_id == course_id)
        .all()
    )
    return random.choice(questions) if questions else None


@router.get("", response_model=schemas.DailyEggStatus)
def get_status(
    course_id: str = Query(...),
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user),
):
    latest = (
        db.query(models.DailyEgg)
        .filter(models.DailyEgg.user_id == current_user.id)
        .order_by(models.DailyEgg.issued_at.desc())
        .first()
    )

    # A pending (unanswered) challenge is always shown again — same question
    # until it's actually answered, regardless of the cooldown.
    if latest is not None and latest.answered_at is None:
        question = db.query(models.Question).filter(models.Question.id == latest.question_id).first()
        return schemas.DailyEggStatus(
            available=True,
            next_available_at=None,
            question=serializers.question_out(db, current_user.id, question),
            level=current_user.level,
        )

    if latest is not None:
        next_at = latest.answered_at + COOLDOWN
        if datetime.datetime.utcnow() < next_at:
            return schemas.DailyEggStatus(
                available=False, next_available_at=next_at, question=None, level=current_user.level
            )

    question = _random_question(db, course_id)
    if question is None:
        return schemas.DailyEggStatus(available=False, next_available_at=None, question=None, level=current_user.level)

    db.add(models.DailyEgg(user_id=current_user.id, question_id=question.id))
    db.commit()
    return schemas.DailyEggStatus(
        available=True,
        next_available_at=None,
        question=serializers.question_out(db, current_user.id, question),
        level=current_user.level,
    )


@router.post("/answer", response_model=schemas.DailyEggAnswerResponse)
def answer(
    payload: schemas.DailyEggAnswerRequest,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user),
):
    latest = (
        db.query(models.DailyEgg)
        .filter(models.DailyEgg.user_id == current_user.id, models.DailyEgg.question_id == payload.question_id)
        .order_by(models.DailyEgg.issued_at.desc())
        .first()
    )
    if latest is None or latest.answered_at is not None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="No pending daily egg challenge for this question"
        )

    # Also feeds normal progress/mistake tracking, same as answering it
    # through the regular subject path.
    question = db.query(models.Question).filter(models.Question.id == payload.question_id).first()
    if question is not None:
        serializers.record_node_answer(db, current_user, question, payload.is_correct)

    latest.answered_at = datetime.datetime.utcnow()
    latest.is_correct = payload.is_correct

    leveled_up = payload.is_correct
    if payload.is_correct:
        current_user.egg_balance += BONUS_EGGS
        current_user.level += 1

    db.commit()
    db.refresh(current_user)

    return schemas.DailyEggAnswerResponse(
        is_correct=payload.is_correct,
        egg_balance=current_user.egg_balance,
        level=current_user.level,
        leveled_up=leveled_up,
        next_available_at=latest.answered_at + COOLDOWN,
    )
