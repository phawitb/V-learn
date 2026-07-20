import datetime
from typing import List

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

import auth
import models
import schemas
import serializers
from database import get_db

router = APIRouter(prefix="/courses", tags=["courses"])

# Pure question-bank courses (no rented video) get a generous, uniform
# validity window once enrolled.
ENROLLMENT_HOURS = 24 * 90


def _get_enrollment(db: Session, user_id: int, course_id: str) -> models.Enrollment:
    enrollment = (
        db.query(models.Enrollment)
        .filter(models.Enrollment.user_id == user_id, models.Enrollment.course_id == course_id)
        .first()
    )
    if enrollment is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Course not found or not enrolled")
    return enrollment


@router.get("/catalog", response_model=List[schemas.CourseCatalogOut])
def list_catalog(
    db: Session = Depends(get_db), current_user: models.User = Depends(auth.get_current_user)
):
    enrolled_ids = {
        e.course_id
        for e in db.query(models.Enrollment).filter(models.Enrollment.user_id == current_user.id).all()
    }
    courses = db.query(models.Course).order_by(models.Course.order_index).all()
    return [serializers.course_catalog_out(c, c.id in enrolled_ids) for c in courses]


@router.post("/{course_id}/enroll", response_model=schemas.CourseSummaryOut, status_code=status.HTTP_201_CREATED)
def enroll(
    course_id: str,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user),
):
    course = db.query(models.Course).filter(models.Course.id == course_id).first()
    if course is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Course not found")

    enrollment = (
        db.query(models.Enrollment)
        .filter(models.Enrollment.user_id == current_user.id, models.Enrollment.course_id == course_id)
        .first()
    )
    if enrollment is None:
        enrollment = models.Enrollment(
            user_id=current_user.id,
            course_id=course_id,
            purchased_at=datetime.datetime.utcnow(),
            expires_at=datetime.datetime.utcnow() + datetime.timedelta(hours=ENROLLMENT_HOURS),
        )
        db.add(enrollment)
        db.commit()
        db.refresh(enrollment)

    return serializers.course_summary_out(db, current_user.id, course, enrollment)


@router.get("", response_model=List[schemas.CourseSummaryOut])
def list_courses(
    db: Session = Depends(get_db), current_user: models.User = Depends(auth.get_current_user)
):
    enrollments = (
        db.query(models.Enrollment)
        .filter(models.Enrollment.user_id == current_user.id)
        .all()
    )
    courses_by_id = {c.id: c for c in db.query(models.Course).order_by(models.Course.order_index).all()}
    out = []
    for enrollment in enrollments:
        course = courses_by_id.get(enrollment.course_id)
        if course is None:
            continue
        out.append(serializers.course_summary_out(db, current_user.id, course, enrollment))
    out.sort(key=lambda c: courses_by_id[c.id].order_index)
    return out


@router.get("/{course_id}", response_model=schemas.CourseDetailOut)
def get_course(
    course_id: str,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user),
):
    course = db.query(models.Course).filter(models.Course.id == course_id).first()
    if course is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Course not found")
    enrollment = _get_enrollment(db, current_user.id, course_id)
    return serializers.course_detail_out(db, current_user.id, course, enrollment)
