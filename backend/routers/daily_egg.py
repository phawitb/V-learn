import datetime
import random

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pymongo.database import Database

import auth
import schemas
import serializers
from database import get_db, next_id

router = APIRouter(prefix="/eggs/daily", tags=["daily-egg"])

COOLDOWN = datetime.timedelta(hours=4)
BONUS_EGGS = 1


def _random_question(db: Database, course_id: str) -> dict | None:
    unit_ids = [u["id"] for u in db.mission_units.find({"course_id": course_id}, {"id": 1}, batch_size=10000)]
    if not unit_ids:
        return None
    node_ids = [n["id"] for n in db.mission_nodes.find({"unit_id": {"$in": unit_ids}}, {"id": 1}, batch_size=10000)]
    if not node_ids:
        return None
    questions = list(db.questions.find({"node_id": {"$in": node_ids}}, batch_size=10000))
    return random.choice(questions) if questions else None


@router.get("", response_model=schemas.DailyEggStatus)
def get_status(
    course_id: str = Query(...),
    db: Database = Depends(get_db),
    current_user: dict = Depends(auth.get_current_user),
):
    latest = db.daily_eggs.find_one({"user_id": current_user["id"]}, sort=[("issued_at", -1)])

    # A pending (unanswered) challenge is always shown again — same question
    # until it's actually answered, regardless of the cooldown.
    if latest is not None and latest.get("answered_at") is None:
        question = db.questions.find_one({"id": latest["question_id"]})
        return schemas.DailyEggStatus(
            available=True,
            next_available_at=None,
            question=serializers.question_out(db, current_user["id"], question),
            level=current_user["level"],
        )

    if latest is not None:
        next_at = latest["answered_at"] + COOLDOWN
        if datetime.datetime.utcnow() < next_at:
            return schemas.DailyEggStatus(
                available=False, next_available_at=next_at, question=None, level=current_user["level"]
            )

    question = _random_question(db, course_id)
    if question is None:
        return schemas.DailyEggStatus(available=False, next_available_at=None, question=None, level=current_user["level"])

    db.daily_eggs.insert_one(
        {
            "id": next_id("daily_eggs"),
            "user_id": current_user["id"],
            "question_id": question["id"],
            "issued_at": datetime.datetime.utcnow(),
            "answered_at": None,
            "is_correct": None,
        }
    )
    return schemas.DailyEggStatus(
        available=True,
        next_available_at=None,
        question=serializers.question_out(db, current_user["id"], question),
        level=current_user["level"],
    )


@router.post("/answer", response_model=schemas.DailyEggAnswerResponse)
def answer(
    payload: schemas.DailyEggAnswerRequest,
    db: Database = Depends(get_db),
    current_user: dict = Depends(auth.get_current_user),
):
    latest = db.daily_eggs.find_one(
        {"user_id": current_user["id"], "question_id": payload.question_id}, sort=[("issued_at", -1)]
    )
    if latest is None or latest.get("answered_at") is not None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="No pending daily egg challenge for this question"
        )

    # Also feeds normal progress/mistake tracking, same as answering it
    # through the regular subject path.
    question = db.questions.find_one({"id": payload.question_id})
    if question is not None:
        serializers.record_node_answer(db, current_user, question, payload.is_correct)

    answered_at = datetime.datetime.utcnow()
    db.daily_eggs.update_one(
        {"_id": latest["_id"]}, {"$set": {"answered_at": answered_at, "is_correct": payload.is_correct}}
    )

    leveled_up = payload.is_correct
    update = {"$inc": {"egg_balance": BONUS_EGGS, "level": 1}} if payload.is_correct else None
    if update:
        db.users.update_one({"id": current_user["id"]}, update)
    user = db.users.find_one({"id": current_user["id"]})

    return schemas.DailyEggAnswerResponse(
        is_correct=payload.is_correct,
        egg_balance=user["egg_balance"],
        level=user["level"],
        leveled_up=leveled_up,
        next_available_at=answered_at + COOLDOWN,
    )
