"""
One-off extraction: reads the verified questions from the sibling
AFAPS-Exam project and bakes them into backend/data/afaps_content.json,
already shaped into V-Learn's course/unit/node/question structure.

Only rows with verificationStatus == "verified" are used — AFAPS-Exam's
own review policy is that unreviewed OCR output ("needs_review") must not
be published, and V-Learn inherits that same rule.

Courses map to AFAPS-Exam's own exam categories (the `docs/exam-pdfs/NN-*`
folder layout), not individual source PDFs:
  01-gpa-phak-a                                -> ก.พ. ภาค ก.
  02-local-exam                                -> สอบท้องถิ่น
  03-police-sergeant                           -> สอบนายสิบตำรวจ
  04-prep-military / 05-police-cadet /
  06-air-force-cadet / 07-naval-cadet          -> สอบเตรียมทหาร
  (+ the standalone จปร. 2567 paper, which also feeds สอบเตรียมทหาร)

Each course's mission units are its subjects; a category with zero
verified questions still gets a course entry (empty mission_units) so the
app can show an honest "not published yet" state rather than hiding it.

Run once from backend/:
    python3 scripts/import_afaps.py
"""

import json
import re
from collections import defaultdict
from pathlib import Path

SOURCE = Path("/Users/phawit/Projects/AFAPS-Exam/data/extracted/questions.json")
OUT = Path(__file__).resolve().parent.parent / "data" / "afaps_content.json"

QUESTIONS_PER_NODE = 10
MIN_NODE_SIZE = 5


def chunk_ranges(total: int, size: int = QUESTIONS_PER_NODE, min_size: int = MIN_NODE_SIZE) -> list[tuple[int, int]]:
    """Split `total` items into (start, end) ranges of ~`size` items each.
    A final remainder smaller than `min_size` is folded into the previous
    chunk instead of forming its own tiny set, so the last chunk may run
    past `size`."""
    ranges = []
    start = 0
    while start < total:
        remaining = total - start
        if remaining <= size or remaining - size < min_size:
            ranges.append((start, total))
            break
        ranges.append((start, start + size))
        start += size
    return ranges

# Ordered: (course_id, code, title, matching source-path prefixes)
MAIN_COURSES = [
    (
        "gpa-phak-a",
        "GPA-A",
        "ก.พ. ภาค ก.",
        ("docs/exam-pdfs/01-gpa-phak-a/",),
    ),
    (
        "local-exam",
        "LOCAL",
        "สอบท้องถิ่น",
        ("docs/exam-pdfs/02-local-exam/",),
    ),
    (
        "police-sergeant",
        "POL-SGT",
        "สอบนายสิบตำรวจ",
        ("docs/exam-pdfs/03-police-sergeant/",),
    ),
    (
        "military-prep",
        "MIL-PREP",
        "สอบเตรียมทหาร",
        (
            "docs/exam-pdfs/04-prep-military/",
            "docs/exam-pdfs/05-police-cadet/",
            "docs/exam-pdfs/06-air-force-cadet/",
            "docs/exam-pdfs/07-naval-cadet/",
            "docs/3-ชุดที่1_แบบทั่วไป_2567.pdf",
        ),
    ),
]

FALLBACK_EXPLANATION = "ตรวจสอบคำตอบที่ถูกต้องจากตัวเลือกด้านบน เอกสารต้นฉบับไม่มีคำอธิบายเพิ่มเติมสำหรับข้อนี้"


def slugify(text: str, fallback: str) -> str:
    text = (text or "").strip()
    if not text:
        return fallback
    slug = re.sub(r"[^\w]+", "-", text, flags=re.UNICODE).strip("-").lower()
    return slug or fallback


def categorize(source_file: str) -> str | None:
    for course_id, _code, _title, prefixes in MAIN_COURSES:
        if source_file.startswith(prefixes):
            return course_id
    return None


def main():
    with SOURCE.open(encoding="utf-8") as f:
        rows = json.load(f)

    verified = [r for r in rows if r.get("verificationStatus") == "verified"]

    unmatched = [r for r in verified if categorize(r["sourceFile"]) is None]
    if unmatched:
        print(f"WARNING: {len(unmatched)} verified rows didn't match any course category:")
        for r in unmatched[:10]:
            print(f"  {r['sourceFile']}")

    # course_id -> subject -> [rows]
    by_course: dict[str, dict[str, list]] = defaultdict(lambda: defaultdict(list))
    for r in verified:
        course_id = categorize(r["sourceFile"])
        if course_id is None:
            continue
        by_course[course_id][r.get("subject") or "อื่นๆ"].append(r)

    courses = []
    skipped = []

    for course_id, code, title, _prefixes in MAIN_COURSES:
        subjects = by_course.get(course_id, {})

        mission_units = []
        for subject_name, subject_rows in sorted(subjects.items(), key=lambda kv: -len(kv[1])):
            unit_id = f"{course_id}-{slugify(subject_name, 'subject')}"

            nodes = []
            for node_no, (chunk_start, chunk_end) in enumerate(chunk_ranges(len(subject_rows)), start=1):
                chunk = subject_rows[chunk_start:chunk_end]
                node_id = f"{unit_id}-n{node_no}"

                questions = []
                for r in chunk:
                    labels = [c["label"] for c in r["choices"]]
                    correct = r.get("correctAnswer")
                    if correct not in labels:
                        skipped.append(r["id"])
                        continue
                    correct_index = labels.index(correct)
                    questions.append(
                        {
                            "id": r["id"],
                            "topic_tag": unit_id,
                            "prompt": r["questionText"].strip(),
                            "choices": [c["text"].strip() for c in r["choices"]],
                            "correct_index": correct_index,
                            "step_solution": (r.get("explanation") or "").strip()
                            or FALLBACK_EXPLANATION,
                        }
                    )

                if not questions:
                    continue

                nodes.append(
                    {
                        "id": node_id,
                        "title": f"{subject_name} · ชุดฝึกที่ {node_no} (ข้อ {chunk_start + 1}-{chunk_start + len(questions)})",
                        "type": "exercise",
                        "lesson_count": 0,
                        "exercise_count": len(questions),
                        "egg_reward": 10 * len(questions),
                        "questions": questions,
                    }
                )

            if nodes:
                mission_units.append(
                    {"id": unit_id, "title": subject_name, "nodes": nodes}
                )

        total_questions = sum(len(n["questions"]) for u in mission_units for n in u["nodes"])
        courses.append(
            {
                "id": course_id,
                "code": code,
                "title": title,
                "source_label": "รวบรวมจากคลังข้อสอบจริง AFAPS-Exam (เฉพาะข้อที่ตรวจสอบแล้ว)",
                "total_questions": total_questions,
                "subject_count": len(mission_units),
                "mission_units": mission_units,
            }
        )

    OUT.parent.mkdir(parents=True, exist_ok=True)
    with OUT.open("w", encoding="utf-8") as f:
        json.dump({"courses": courses}, f, ensure_ascii=False, indent=2)

    print(f"Wrote {OUT}")
    print(f"Courses: {len(courses)}")
    for c in courses:
        print(f"  {c['code']:10s} {c['title']:20s} subjects={c['subject_count']:2d} questions={c['total_questions']}")
        for u in c["mission_units"]:
            qcount = sum(len(n["questions"]) for n in u["nodes"])
            print(f"      - {u['title']:35s} {qcount} ข้อ")
    print(f"Skipped (bad correctAnswer): {len(skipped)} {skipped}")


if __name__ == "__main__":
    main()
