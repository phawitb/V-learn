import datetime
from typing import List

from fastapi import APIRouter, Depends, HTTPException, status
from pymongo.database import Database

import auth
import schemas
import serializers
from database import get_db, next_id

router = APIRouter(prefix="/courses", tags=["courses"])

# Pure question-bank courses (no rented video) get a generous, uniform
# validity window once enrolled.
ENROLLMENT_HOURS = 24 * 90


def _get_enrollment(db: Database, user_id: int, course_id: str) -> dict:
    enrollment = db.enrollments.find_one({"user_id": user_id, "course_id": course_id})
    if enrollment is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Course not found or not enrolled")
    return enrollment


@router.get("/catalog", response_model=List[schemas.CourseCatalogOut])
def list_catalog(db: Database = Depends(get_db), current_user: dict = Depends(auth.get_current_user)):
    enrolled_ids = {e["course_id"] for e in db.enrollments.find({"user_id": current_user["id"]}, batch_size=10000)}
    courses = list(db.courses.find(batch_size=10000).sort("order_index"))
    return serializers.course_catalog_entries_out(db, courses, enrolled_ids)


@router.post("/{course_id}/enroll", response_model=schemas.CourseSummaryOut, status_code=status.HTTP_201_CREATED)
def enroll(
    course_id: str,
    db: Database = Depends(get_db),
    current_user: dict = Depends(auth.get_current_user),
):
    course = db.courses.find_one({"id": course_id})
    if course is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Course not found")

    enrollment = db.enrollments.find_one({"user_id": current_user["id"], "course_id": course_id})
    if enrollment is None:
        enrollment = {
            "id": next_id("enrollments"),
            "user_id": current_user["id"],
            "course_id": course_id,
            "purchased_at": datetime.datetime.utcnow(),
            "expires_at": datetime.datetime.utcnow() + datetime.timedelta(hours=ENROLLMENT_HOURS),
            "last_episode_id": None,
        }
        db.enrollments.insert_one(enrollment)

    return serializers.course_summary_out(db, current_user["id"], course, enrollment)


@router.get("", response_model=List[schemas.CourseSummaryOut])
def list_courses(db: Database = Depends(get_db), current_user: dict = Depends(auth.get_current_user)):
    enrollment_by_course_id = {e["course_id"]: e for e in db.enrollments.find({"user_id": current_user["id"]}, batch_size=10000)}
    if not enrollment_by_course_id:
        return []
    courses = list(db.courses.find({"id": {"$in": list(enrollment_by_course_id.keys())}}, batch_size=10000).sort("order_index"))
    return serializers.course_summaries_out(db, current_user["id"], courses, enrollment_by_course_id)


@router.get("/{course_id}", response_model=schemas.CourseDetailOut)
def get_course(
    course_id: str,
    db: Database = Depends(get_db),
    current_user: dict = Depends(auth.get_current_user),
):
    course = db.courses.find_one({"id": course_id})
    if course is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Course not found")
    enrollment = _get_enrollment(db, current_user["id"], course_id)
    return serializers.course_detail_out(db, current_user["id"], course, enrollment)
