import datetime
from typing import List

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pymongo.database import Database

import auth
import schemas
import serializers
from database import get_db, next_id

router = APIRouter(prefix="/questions", tags=["questions"])


@router.get("/by-ids", response_model=List[schemas.QuestionOut])
def questions_by_ids(
    ids: str = Query(..., description="Comma-separated question ids"),
    db: Database = Depends(get_db),
    current_user: dict = Depends(auth.get_current_user),
):
    id_list = [i for i in ids.split(",") if i]
    rows_by_id = {q["id"]: q for q in db.questions.find({"id": {"$in": id_list}}, batch_size=10000)}
    ordered = [rows_by_id[i] for i in id_list if i in rows_by_id]
    answers, saved_ids, reported_ids = serializers.progress_maps(db, current_user["id"], [q["id"] for q in ordered])
    return [
        serializers.build_question_out(q, answers.get(q["id"]), q["id"] in saved_ids, q["id"] in reported_ids)
        for q in ordered
    ]


@router.get("/saved", response_model=List[schemas.MistakeOut])
def list_saved_questions(db: Database = Depends(get_db), current_user: dict = Depends(auth.get_current_user)):
    """Bookmarked questions, shaped identically to /mistakes so ทบทวน can
    group and render both the same way — a question's topic_tag is always
    its owning subject's unit id."""
    rows = list(db.saved_questions.find({"user_id": current_user["id"]}, batch_size=10000).sort("saved_at", -1))
    question_ids = [r["question_id"] for r in rows]
    questions_by_id = {q["id"]: q for q in db.questions.find({"id": {"$in": question_ids}}, batch_size=10000)}
    units_by_id = {u["id"]: u for u in db.mission_units.find(batch_size=10000)}
    courses_by_id = {c["id"]: c for c in db.courses.find(batch_size=10000)}

    out = []
    for r in rows:
        q = questions_by_id.get(r["question_id"])
        if q is None:
            continue
        unit = units_by_id.get(q["topic_tag"])
        course_id = unit["course_id"] if unit else ""
        out.append(
            schemas.MistakeOut(
                question_id=q["id"],
                topic_tag=q["topic_tag"],
                course_id=course_id,
                course_title=courses_by_id.get(course_id, {}).get("title", ""),
                unit_title=unit["title"] if unit else q["topic_tag"],
                question_prompt=q["prompt"],
            )
        )
    return out


@router.post("/{question_id}/answer", response_model=schemas.AnswerRecordResponse)
def record_answer(
    question_id: str,
    payload: schemas.AnswerRecordRequest,
    db: Database = Depends(get_db),
    current_user: dict = Depends(auth.get_current_user),
):
    # The owning node comes from the question itself, not a client-supplied
    # id — Mistake Hunter replays variant questions from other nodes through
    # the same flow, so trusting the caller could misattribute progress.
    question = db.questions.find_one({"id": question_id})
    if question is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Question not found")

    awarded = serializers.record_node_answer(db, current_user, question, payload.is_correct, payload.selected_index)
    user = db.users.find_one({"id": current_user["id"]})
    return schemas.AnswerRecordResponse(egg_balance=user["egg_balance"], awarded=awarded)


@router.post("/reset-progress", status_code=status.HTTP_204_NO_CONTENT)
def reset_progress(
    payload: schemas.ResetProgressRequest,
    db: Database = Depends(get_db),
    current_user: dict = Depends(auth.get_current_user),
):
    """Clears answered/correct state for the given questions (used by the
    สารบัญ "reset" button) — leaves saved/reported flags untouched, since
    those are separate, deliberate actions rather than "progress"."""
    db.node_answers.delete_many({"user_id": current_user["id"], "question_id": {"$in": payload.question_ids}})


@router.post("/{question_id}/save", status_code=status.HTTP_204_NO_CONTENT)
def save_question(
    question_id: str,
    db: Database = Depends(get_db),
    current_user: dict = Depends(auth.get_current_user),
):
    question = db.questions.find_one({"id": question_id})
    if question is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Question not found")

    existing = db.saved_questions.find_one({"user_id": current_user["id"], "question_id": question_id})
    if existing is None:
        db.saved_questions.insert_one(
            {
                "id": next_id("saved_questions"),
                "user_id": current_user["id"],
                "question_id": question_id,
                "saved_at": datetime.datetime.utcnow(),
            }
        )


@router.delete("/{question_id}/save", status_code=status.HTTP_204_NO_CONTENT)
def unsave_question(
    question_id: str,
    db: Database = Depends(get_db),
    current_user: dict = Depends(auth.get_current_user),
):
    db.saved_questions.delete_one({"user_id": current_user["id"], "question_id": question_id})


@router.post("/{question_id}/report", status_code=status.HTTP_201_CREATED)
def report_question(
    question_id: str,
    payload: schemas.QuestionReportRequest,
    db: Database = Depends(get_db),
    current_user: dict = Depends(auth.get_current_user),
):
    question = db.questions.find_one({"id": question_id})
    if question is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Question not found")

    db.question_reports.insert_one(
        {
            "id": next_id("question_reports"),
            "user_id": current_user["id"],
            "question_id": question_id,
            "message": payload.message,
        }
    )
    return {"status": "received"}
