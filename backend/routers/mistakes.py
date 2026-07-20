import datetime
from typing import List

from fastapi import APIRouter, Depends, status
from pymongo.database import Database

import auth
import schemas
from database import get_db, next_id

router = APIRouter(prefix="/mistakes", tags=["mistakes"])


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
    )


@router.delete("/{question_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_mistake(
    question_id: str,
    db: Database = Depends(get_db),
    current_user: dict = Depends(auth.get_current_user),
):
    db.mistakes.delete_one({"user_id": current_user["id"], "question_id": question_id})
