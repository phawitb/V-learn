import datetime
from typing import List

from fastapi import APIRouter, Depends, status
from pymongo.database import Database

import auth
import schemas
from database import get_db, next_id

router = APIRouter(prefix="/mistakes", tags=["mistakes"])

# A mistake only drops off ทบทวน once its variant has been answered
# correctly this many times — a single lucky guess shouldn't clear it.
CORRECT_COUNT_TO_CLEAR = 3


@router.get("", response_model=List[schemas.MistakeOut])
def list_mistakes(db: Database = Depends(get_db), current_user: dict = Depends(auth.get_current_user)):
    rows = list(db.mistakes.find({"user_id": current_user["id"]}, batch_size=10000).sort("created_at", -1))
    courses_by_id = {c["id"]: c for c in db.courses.find(batch_size=10000)}
    # A question's topic_tag is always its owning subject's unit id, so this
    # is how mistakes get grouped by subject in the UI without a new column.
    units_by_id = {u["id"]: u for u in db.mission_units.find(batch_size=10000)}
    return [
        schemas.MistakeOut(
            question_id=m["question_id"],
            topic_tag=m["topic_tag"],
            course_id=m["course_id"],
            course_title=courses_by_id[m["course_id"]]["title"] if m["course_id"] in courses_by_id else "",
            unit_title=units_by_id[m["topic_tag"]]["title"] if m["topic_tag"] in units_by_id else m["topic_tag"],
            question_prompt=m["question_prompt"],
            correct_count=m.get("correct_count", 0),
        )
        for m in rows
    ]


@router.post("", response_model=schemas.MistakeOut, status_code=status.HTTP_201_CREATED)
def create_mistake(
    payload: schemas.MistakeCreateRequest,
    db: Database = Depends(get_db),
    current_user: dict = Depends(auth.get_current_user),
):
    existing = db.mistakes.find_one({"user_id": current_user["id"], "question_id": payload.question_id})
    if existing is None:
        db.mistakes.insert_one(
            {
                "id": next_id("mistakes"),
                "user_id": current_user["id"],
                "question_id": payload.question_id,
                "topic_tag": payload.topic_tag,
                "course_id": payload.course_id,
                "question_prompt": payload.question_prompt,
                "correct_count": 0,
                "created_at": datetime.datetime.utcnow(),
            }
        )

    course = db.courses.find_one({"id": payload.course_id})
    unit = db.mission_units.find_one({"id": payload.topic_tag})
    return schemas.MistakeOut(
        question_id=payload.question_id,
        topic_tag=payload.topic_tag,
        course_id=payload.course_id,
        course_title=course["title"] if course else "",
        unit_title=unit["title"] if unit else payload.topic_tag,
        question_prompt=payload.question_prompt,
        correct_count=existing.get("correct_count", 0) if existing else 0,
    )


@router.delete("/{question_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_mistake(
    question_id: str,
    db: Database = Depends(get_db),
    current_user: dict = Depends(auth.get_current_user),
):
    db.mistakes.delete_one({"user_id": current_user["id"], "question_id": question_id})


@router.post("/{question_id}/retry", response_model=schemas.MistakeRetryOut)
def record_mistake_retry(
    question_id: str,
    payload: schemas.MistakeRetryRequest,
    db: Database = Depends(get_db),
    current_user: dict = Depends(auth.get_current_user),
):
    """Called after answering a mistake's (randomized) variant question —
    only correct answers count toward CORRECT_COUNT_TO_CLEAR, and the
    counter never resets on a wrong one, so a re-randomized retry a few
    days later still adds up instead of punishing an unlucky guess."""
    mistake = db.mistakes.find_one({"user_id": current_user["id"], "question_id": question_id})
    if mistake is None:
        return schemas.MistakeRetryOut(correct_count=0, cleared=True)
    if not payload.correct:
        return schemas.MistakeRetryOut(correct_count=mistake.get("correct_count", 0), cleared=False)

    new_count = mistake.get("correct_count", 0) + 1
    if new_count >= CORRECT_COUNT_TO_CLEAR:
        db.mistakes.delete_one({"_id": mistake["_id"]})
        return schemas.MistakeRetryOut(correct_count=new_count, cleared=True)

    db.mistakes.update_one({"_id": mistake["_id"]}, {"$set": {"correct_count": new_count}})
    return schemas.MistakeRetryOut(correct_count=new_count, cleared=False)
