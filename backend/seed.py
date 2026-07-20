import json
import random
from pathlib import Path

from sqlalchemy.orm import Session

import models

CONTENT_FILE = Path(__file__).resolve().parent / "data" / "afaps_content.json"

# course_id -> (gradient start, gradient end), so the 4 exam categories are
# visually distinct on the course list.
THUMB_COLORS = {
    "gpa-phak-a": ("#3F6BEA", "#7FD0EE"),
    "local-exam": ("#2E9E83", "#7FE0C0"),
    "police-sergeant": ("#3949AB", "#7986CB"),
    "military-prep": ("#C0392B", "#F2B8A0"),
}
DEFAULT_THUMB_COLORS = ("#3F6BEA", "#7FD0EE")


def seed_if_empty(db: Session) -> None:
    if db.query(models.Course).count() > 0:
        return

    with CONTENT_FILE.open(encoding="utf-8") as f:
        content = json.load(f)

    for order_index, course_data in enumerate(content["courses"]):
        thumb_start, thumb_end = THUMB_COLORS.get(course_data["id"], DEFAULT_THUMB_COLORS)
        course = models.Course(
            id=course_data["id"],
            code=course_data["code"],
            title=course_data["title"],
            instructor=course_data["source_label"],
            thumb_color_start=thumb_start,
            thumb_color_end=thumb_end,
            total_hours=max(1, round(course_data["total_questions"] / 20)),
            has_eggspace=bool(course_data["mission_units"]),
            order_index=order_index,
        )
        db.add(course)

        for unit_order, unit_data in enumerate(course_data["mission_units"]):
            unit = models.MissionUnit(
                id=unit_data["id"],
                course_id=course.id,
                title=unit_data["title"],
                order_index=unit_order,
            )
            db.add(unit)

            for node_order, node_data in enumerate(unit_data["nodes"]):
                node = models.MissionNode(
                    id=node_data["id"],
                    unit_id=unit.id,
                    title=node_data["title"],
                    type=node_data["type"],
                    lesson_count=node_data["lesson_count"],
                    exercise_count=node_data["exercise_count"],
                    youtube_id=None,
                    egg_reward=node_data["egg_reward"],
                    order_index=node_order,
                )
                db.add(node)

                for q_order, q_data in enumerate(node_data["questions"]):
                    db.add(
                        models.Question(
                            id=q_data["id"],
                            node_id=node.id,
                            topic_tag=q_data["topic_tag"],
                            prompt=q_data["prompt"],
                            choices=q_data["choices"],
                            correct_index=q_data["correct_index"],
                            step_solution=q_data["step_solution"],
                            order_index=q_order,
                        )
                    )

    db.commit()


# Real-exam-informed mock exam blueprints: subject -> {count, points}.
# เตรียมทหาร matches the real published format exactly (225 questions /
# 700 points / 210 minutes) since the verified question bank happens to
# hold precisely the real per-subject counts. The current ก.พ. ภาค ก.
# exam was reformed into 3 subjects (ความสามารถในการคิดวิเคราะห์ /
# ภาษาอังกฤษ / ความรู้และลักษณะการเป็นข้าราชการที่ดี) that don't exist as
# verified subject tags in our question bank yet — until that content is
# verified upstream in AFAPS-Exam, this blueprint keeps the older
# 5-subject ก.พ. categorization our verified content actually has, sized
# to the same real total (100 questions / 200 points / 180 minutes).
EXAM_BLUEPRINTS = {
    "gpa-phak-a": {
        "duration_minutes": 180,
        "subjects": {
            "ความรู้ความสามารถทั่วไป": {"count": 33, "points": 2},
            "ภาษาไทย": {"count": 30, "points": 2},
            "ความสามารถด้านคำนวณ": {"count": 16, "points": 2},
            "ภาษาอังกฤษ": {"count": 11, "points": 2},
            "ความสามารถด้านเหตุผล": {"count": 10, "points": 2},
        },
    },
    "military-prep": {
        "duration_minutes": 210,
        "subjects": {
            "คณิตศาสตร์": {"count": 50, "points": 4},
            "วิทยาศาสตร์": {"count": 50, "points": 4},
            "ภาษาอังกฤษ": {"count": 50, "points": 3},
            "ภาษาไทย": {"count": 30, "points": 2},
            "สังคมศึกษา ศาสนา และวัฒนธรรม": {"count": 45, "points": 2},
        },
    },
}
MOCK_EXAM_SETS_PER_COURSE = 2


def seed_mock_exams(db: Session) -> None:
    if db.query(models.MockExamSet).count() > 0:
        return

    for course_id, blueprint in EXAM_BLUEPRINTS.items():
        course = db.query(models.Course).filter(models.Course.id == course_id).first()
        if course is None:
            continue
        units_by_title = {u.title: u for u in course.mission_units}

        for set_no in range(1, MOCK_EXAM_SETS_PER_COURSE + 1):
            exam_set = models.MockExamSet(
                id=f"{course_id}-mock-{set_no}",
                course_id=course_id,
                title=f"ชุดที่ {set_no}",
                order_index=set_no,
                duration_minutes=blueprint["duration_minutes"],
            )
            db.add(exam_set)

            order_index = 0
            for subject_title, spec in blueprint["subjects"].items():
                unit = units_by_title.get(subject_title)
                if unit is None:
                    continue
                question_ids = [q.id for node in unit.nodes for q in node.questions]
                if not question_ids:
                    continue
                chosen = random.sample(question_ids, min(spec["count"], len(question_ids)))
                for qid in chosen:
                    db.add(
                        models.MockExamQuestion(
                            exam_set_id=exam_set.id,
                            question_id=qid,
                            subject_title=subject_title,
                            points=spec["points"],
                            order_index=order_index,
                        )
                    )
                    order_index += 1

    db.commit()
