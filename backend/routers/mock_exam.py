import datetime
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pymongo import UpdateOne
from pymongo.database import Database

import auth
import schemas
from database import get_db, next_id, next_id_batch

router = APIRouter(tags=["mock-exam"])


def _mock_exam_questions(db: Database, exam_set_id: str) -> List[dict]:
    return list(db.mock_exam_questions.find({"exam_set_id": exam_set_id}, batch_size=10000).sort("order_index"))


def _saved_reported_ids(db: Database, user_id: int, question_ids: List[str]) -> tuple[set[str], set[str]]:
    saved_ids = {
        r["question_id"] for r in db.saved_questions.find({"user_id": user_id, "question_id": {"$in": question_ids}}, batch_size=10000)
    }
    reported_ids = {
        r["question_id"]
        for r in db.question_reports.find({"user_id": user_id, "question_id": {"$in": question_ids}}, batch_size=10000)
    }
    return saved_ids, reported_ids


def _in_progress_attempt(db: Database, user_id: int, exam_set_id: str) -> Optional[dict]:
    return db.mock_exam_attempts.find_one(
        {"user_id": user_id, "exam_set_id": exam_set_id, "submitted_at": None},
        sort=[("started_at", -1)],
    )


@router.get("/courses/{course_id}/mock-exams", response_model=List[schemas.MockExamSetOut])
def list_mock_exams(
    course_id: str,
    db: Database = Depends(get_db),
    current_user: dict = Depends(auth.get_current_user),
):
    exam_sets = list(db.mock_exam_sets.find({"course_id": course_id}, batch_size=10000).sort("order_index"))
    if not exam_sets:
        return []
    exam_set_ids = [s["id"] for s in exam_sets]

    # Batched across every exam set in the course (3 queries total) instead
    # of 2-3 queries *per set* — this endpoint fires every time the learner
    # returns to Home from a mock exam, and each query pays real network
    # round-trip time against Atlas, so per-set queries add up fast.
    questions_by_set: dict[str, list[dict]] = {}
    for mq in db.mock_exam_questions.find({"exam_set_id": {"$in": exam_set_ids}}, batch_size=10000):
        questions_by_set.setdefault(mq["exam_set_id"], []).append(mq)

    attempt_by_set: dict[str, dict] = {}
    for a in db.mock_exam_attempts.find(
        {"user_id": current_user["id"], "exam_set_id": {"$in": exam_set_ids}, "submitted_at": None}
    ):
        existing = attempt_by_set.get(a["exam_set_id"])
        if existing is None or a["started_at"] > existing["started_at"]:
            attempt_by_set[a["exam_set_id"]] = a

    attempt_ids = [a["id"] for a in attempt_by_set.values()]
    latest_answer_by_attempt: dict[int, dict] = {}
    if attempt_ids:
        for ans in db.mock_exam_answers.find({"attempt_id": {"$in": attempt_ids}}, batch_size=10000).sort("updated_at", -1):
            latest_answer_by_attempt.setdefault(ans["attempt_id"], ans)

    out = []
    for exam_set in exam_sets:
        by_subject: dict[str, dict] = {}
        for mq in questions_by_set.get(exam_set["id"], []):
            entry = by_subject.setdefault(mq["subject_title"], {"count": 0, "points": mq["points"]})
            entry["count"] += 1
        subjects = [
            schemas.MockExamSubjectOut(
                title=title,
                count=data["count"],
                points_per_question=data["points"],
                total_points=data["count"] * data["points"],
            )
            for title, data in by_subject.items()
        ]

        attempt = attempt_by_set.get(exam_set["id"])
        last_activity_at = None
        if attempt is not None:
            latest_answer = latest_answer_by_attempt.get(attempt["id"])
            last_activity_at = (latest_answer["updated_at"] if latest_answer else None) or attempt["started_at"]

        out.append(
            schemas.MockExamSetOut(
                id=exam_set["id"],
                title=exam_set["title"],
                duration_minutes=exam_set["duration_minutes"],
                total_questions=sum(s.count for s in subjects),
                total_points=sum(s.total_points for s in subjects),
                subjects=subjects,
                has_in_progress=attempt is not None,
                last_activity_at=last_activity_at,
            )
        )
    return out


@router.get("/mock-exams/{exam_set_id}/status", response_model=schemas.MockExamStatusOut)
def exam_status(
    exam_set_id: str,
    db: Database = Depends(get_db),
    current_user: dict = Depends(auth.get_current_user),
):
    attempt = _in_progress_attempt(db, current_user["id"], exam_set_id)
    if attempt is None:
        return schemas.MockExamStatusOut(has_in_progress=False)
    answered_count = db.mock_exam_answers.count_documents(
        {"attempt_id": attempt["id"], "selected_index": {"$ne": None}}
    )
    return schemas.MockExamStatusOut(has_in_progress=True, answered_count=answered_count, total_questions=attempt["total"])


@router.post("/mock-exams/{exam_set_id}/start", response_model=schemas.MockExamStartResponse)
def start_exam(
    exam_set_id: str,
    restart: bool = Query(False),
    db: Database = Depends(get_db),
    current_user: dict = Depends(auth.get_current_user),
):
    exam_set = db.mock_exam_sets.find_one({"id": exam_set_id})
    if exam_set is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Mock exam set not found")

    existing = _in_progress_attempt(db, current_user["id"], exam_set_id)
    if existing is not None and restart:
        db.mock_exam_answers.delete_many({"attempt_id": existing["id"]})
        db.mock_exam_attempts.delete_one({"_id": existing["_id"]})
        existing = None

    mock_questions = _mock_exam_questions(db, exam_set_id)
    question_ids = [mq["question_id"] for mq in mock_questions]
    questions_by_id = {q["id"]: q for q in db.questions.find({"id": {"$in": question_ids}}, batch_size=10000)}
    subject_by_qid = {mq["question_id"]: mq["subject_title"] for mq in mock_questions}

    if existing is not None:
        attempt = existing
        saved_answers = {
            a["question_id"]: a["selected_index"]
            for a in db.mock_exam_answers.find({"attempt_id": attempt["id"]}, batch_size=10000)
            if a["selected_index"] is not None
        }
    else:
        attempt = {
            "id": next_id("mock_exam_attempts"),
            "user_id": current_user["id"],
            "exam_set_id": exam_set["id"],
            "started_at": datetime.datetime.utcnow(),
            "submitted_at": None,
            "score": None,
            "total": len(question_ids),
        }
        db.mock_exam_attempts.insert_one(attempt)
        saved_answers = {}

    saved_ids, reported_ids = _saved_reported_ids(db, current_user["id"], question_ids)

    return schemas.MockExamStartResponse(
        attempt_id=attempt["id"],
        exam_set_id=exam_set["id"],
        title=exam_set["title"],
        duration_minutes=exam_set["duration_minutes"],
        started_at=attempt["started_at"],
        answers=saved_answers,
        questions=[
            schemas.ExamQuestionOut(
                id=qid,
                prompt=questions_by_id[qid]["prompt"],
                choices=questions_by_id[qid]["choices"],
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
    db: Database = Depends(get_db),
    current_user: dict = Depends(auth.get_current_user),
):
    attempt = db.mock_exam_attempts.find_one({"id": attempt_id, "user_id": current_user["id"]})
    if attempt is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Attempt not found")
    if attempt.get("submitted_at") is not None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Attempt already submitted")

    now = datetime.datetime.utcnow()
    existing = db.mock_exam_answers.find_one({"attempt_id": attempt_id, "question_id": payload.question_id})
    if existing is not None:
        db.mock_exam_answers.update_one(
            {"_id": existing["_id"]}, {"$set": {"selected_index": payload.selected_index, "updated_at": now}}
        )
    else:
        db.mock_exam_answers.insert_one(
            {
                "id": next_id("mock_exam_answers"),
                "attempt_id": attempt_id,
                "question_id": payload.question_id,
                "selected_index": payload.selected_index,
                "updated_at": now,
            }
        )


@router.post("/mock-exams/attempts/{attempt_id}/submit", response_model=schemas.MockExamResultOut)
def submit_exam(
    attempt_id: int,
    payload: schemas.MockExamSubmitRequest,
    db: Database = Depends(get_db),
    current_user: dict = Depends(auth.get_current_user),
):
    attempt = db.mock_exam_attempts.find_one({"id": attempt_id, "user_id": current_user["id"]})
    if attempt is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Attempt not found")
    if attempt.get("submitted_at") is not None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Attempt already submitted")

    exam_set = db.mock_exam_sets.find_one({"id": attempt["exam_set_id"]})
    mock_questions = {mq["question_id"]: mq for mq in _mock_exam_questions(db, exam_set["id"])}
    question_ids = list(mock_questions.keys())
    questions = {q["id"]: q for q in db.questions.find({"id": {"$in": question_ids}}, batch_size=10000)}
    units_by_id = {u["id"]: u for u in db.mission_units.find(batch_size=10000)}

    # Merge in any autosaved answers not present in this final payload, so a
    # resumed exam that got autosaved answers but a partial final payload
    # still grades everything that was actually selected.
    autosaved = {a["question_id"]: a["selected_index"] for a in db.mock_exam_answers.find({"attempt_id": attempt["id"]}, batch_size=10000)}
    answers = {**autosaved, **payload.answers}
    saved_ids, reported_ids = _saved_reported_ids(db, current_user["id"], question_ids)

    # Grading writes ~1 mistake + ~1 answer row per question (up to 225 for
    # this app's biggest exam). Doing that with a find_one + insert/update
    # *per question* — as this used to — is 400-900+ round trips against a
    # remote Atlas cluster, which is exactly why submitting felt like it
    # hung. Batch every read and write instead: one query to see which
    # mistakes already exist, one bulk_write for all answer upserts, one
    # insert_many for new mistakes.
    existing_mistake_qids = {
        m["question_id"]
        for m in db.mistakes.find(
            {"user_id": current_user["id"], "question_id": {"$in": question_ids}}, {"question_id": 1}
        )
    }
    mistake_ids = iter(next_id_batch("mistakes", len(question_ids)))
    answer_ids = iter(next_id_batch("mock_exam_answers", len(question_ids)))

    now = datetime.datetime.utcnow()
    score = 0
    review = []
    new_mistakes = []
    answer_ops = []
    for qid in question_ids:
        q = questions.get(qid)
        mq = mock_questions[qid]
        if q is None:
            continue
        selected = answers.get(qid)
        is_correct = selected is not None and selected == q["correct_index"]
        if is_correct:
            score += mq["points"]
        # A question left blank was never attempted — it isn't a "mistake"
        # to review, just something the learner didn't get to. Only an
        # actual wrong pick counts.
        elif selected is not None and qid not in existing_mistake_qids:
            unit = units_by_id.get(q["topic_tag"])
            new_mistakes.append(
                {
                    "id": next(mistake_ids),
                    "user_id": current_user["id"],
                    "question_id": qid,
                    "topic_tag": q["topic_tag"],
                    "course_id": unit["course_id"] if unit else exam_set["course_id"],
                    "question_prompt": q["prompt"],
                    "created_at": now,
                }
            )
            existing_mistake_qids.add(qid)

        answer_ops.append(
            UpdateOne(
                {"attempt_id": attempt["id"], "question_id": qid},
                {
                    "$set": {"selected_index": selected, "updated_at": now},
                    "$setOnInsert": {"id": next(answer_ids)},
                },
                upsert=True,
            )
        )

        review.append(
            schemas.ExamReviewQuestionOut(
                id=q["id"],
                prompt=q["prompt"],
                choices=q["choices"],
                correct_index=q["correct_index"],
                step_solution=q["step_solution"],
                subject_title=mq["subject_title"],
                points=mq["points"],
                selected_index=selected,
                is_correct=is_correct,
                saved=qid in saved_ids,
                reported=qid in reported_ids,
            )
        )

    if new_mistakes:
        db.mistakes.insert_many(new_mistakes)
    if answer_ops:
        db.mock_exam_answers.bulk_write(answer_ops)
    db.mock_exam_attempts.update_one({"_id": attempt["_id"]}, {"$set": {"submitted_at": now, "score": score}})

    return schemas.MockExamResultOut(attempt_id=attempt["id"], score=score, total=attempt["total"], questions=review)


@router.get("/mock-exams/attempts", response_model=List[schemas.MockExamAttemptSummaryOut])
def list_attempts(
    course_id: Optional[str] = Query(None),
    db: Database = Depends(get_db),
    current_user: dict = Depends(auth.get_current_user),
):
    attempts = list(
        db.mock_exam_attempts.find({"user_id": current_user["id"], "submitted_at": {"$ne": None}}, batch_size=10000).sort(
            "submitted_at", -1
        )
    )
    exam_sets_by_id = {
        s["id"]: s for s in db.mock_exam_sets.find({"id": {"$in": [a["exam_set_id"] for a in attempts]}}, batch_size=10000)
    }
    out = []
    for attempt in attempts:
        exam_set = exam_sets_by_id.get(attempt["exam_set_id"])
        if exam_set is None:
            continue
        if course_id is not None and exam_set["course_id"] != course_id:
            continue
        out.append(
            schemas.MockExamAttemptSummaryOut(
                attempt_id=attempt["id"],
                exam_set_id=exam_set["id"],
                exam_set_title=exam_set["title"],
                course_id=exam_set["course_id"],
                score=attempt.get("score") or 0,
                total=attempt["total"],
                submitted_at=attempt["submitted_at"],
            )
        )
    return out


@router.get("/mock-exams/attempts/{attempt_id}/result", response_model=schemas.MockExamResultOut)
def get_attempt_result(
    attempt_id: int,
    db: Database = Depends(get_db),
    current_user: dict = Depends(auth.get_current_user),
):
    attempt = db.mock_exam_attempts.find_one({"id": attempt_id, "user_id": current_user["id"]})
    if attempt is None or attempt.get("submitted_at") is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Submitted attempt not found")

    exam_set = db.mock_exam_sets.find_one({"id": attempt["exam_set_id"]})
    mock_questions = {mq["question_id"]: mq for mq in _mock_exam_questions(db, exam_set["id"])}
    question_ids = list(mock_questions.keys())
    questions = {q["id"]: q for q in db.questions.find({"id": {"$in": question_ids}}, batch_size=10000)}
    answers = {a["question_id"]: a["selected_index"] for a in db.mock_exam_answers.find({"attempt_id": attempt["id"]}, batch_size=10000)}
    saved_ids, reported_ids = _saved_reported_ids(db, current_user["id"], question_ids)

    review = []
    for qid in question_ids:
        q = questions.get(qid)
        if q is None:
            continue
        mq = mock_questions[qid]
        selected = answers.get(qid)
        review.append(
            schemas.ExamReviewQuestionOut(
                id=q["id"],
                prompt=q["prompt"],
                choices=q["choices"],
                correct_index=q["correct_index"],
                step_solution=q["step_solution"],
                subject_title=mq["subject_title"],
                points=mq["points"],
                selected_index=selected,
                is_correct=selected is not None and selected == q["correct_index"],
                saved=qid in saved_ids,
                reported=qid in reported_ids,
            )
        )

    return schemas.MockExamResultOut(attempt_id=attempt["id"], score=attempt.get("score") or 0, total=attempt["total"], questions=review)
