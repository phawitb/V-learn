from typing import List

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

import auth
import models
import schemas
from database import get_db

router = APIRouter(prefix="/mistakes", tags=["mistakes"])


@router.get("", response_model=List[schemas.MistakeOut])
def list_mistakes(
    db: Session = Depends(get_db), current_user: models.User = Depends(auth.get_current_user)
):
    rows = (
        db.query(models.Mistake)
        .filter(models.Mistake.user_id == current_user.id)
        .order_by(models.Mistake.created_at.desc())
        .all()
    )
    courses_by_id = {c.id: c for c in db.query(models.Course).all()}
    # A question's topic_tag is always its owning subject's unit id, so this
    # is how mistakes get grouped by subject in the UI without a new column.
    units_by_id = {u.id: u for u in db.query(models.MissionUnit).all()}
    return [
        schemas.MistakeOut(
            question_id=m.question_id,
            topic_tag=m.topic_tag,
            course_id=m.course_id,
            course_title=courses_by_id[m.course_id].title if m.course_id in courses_by_id else "",
            unit_title=units_by_id[m.topic_tag].title if m.topic_tag in units_by_id else m.topic_tag,
            question_prompt=m.question_prompt,
        )
        for m in rows
    ]


@router.post("", response_model=schemas.MistakeOut, status_code=status.HTTP_201_CREATED)
def create_mistake(
    payload: schemas.MistakeCreateRequest,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user),
):
    existing = (
        db.query(models.Mistake)
        .filter(models.Mistake.user_id == current_user.id, models.Mistake.question_id == payload.question_id)
        .first()
    )
    if existing is None:
        db.add(
            models.Mistake(
                user_id=current_user.id,
                question_id=payload.question_id,
                topic_tag=payload.topic_tag,
                course_id=payload.course_id,
                question_prompt=payload.question_prompt,
            )
        )
        db.commit()

    course = db.query(models.Course).filter(models.Course.id == payload.course_id).first()
    unit = db.query(models.MissionUnit).filter(models.MissionUnit.id == payload.topic_tag).first()
    return schemas.MistakeOut(
        question_id=payload.question_id,
        topic_tag=payload.topic_tag,
        course_id=payload.course_id,
        course_title=course.title if course else "",
        unit_title=unit.title if unit else payload.topic_tag,
        question_prompt=payload.question_prompt,
    )


@router.delete("/{question_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_mistake(
    question_id: str,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user),
):
    row = (
        db.query(models.Mistake)
        .filter(models.Mistake.user_id == current_user.id, models.Mistake.question_id == question_id)
        .first()
    )
    if row is not None:
        db.delete(row)
        db.commit()
