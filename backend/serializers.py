import datetime
from typing import Optional

from pymongo.database import Database

import schemas
from database import next_id

# Eggs are earned per question answered (any answer counts — "ทุกข้อคือจุด
# เรียนรู้ ไม่ใช่แค่จุดวัดผล"), now that the path has no "set" to complete.
EGGS_PER_QUESTION = 10


def user_out(user: dict) -> schemas.UserOut:
    profile_complete = bool(user.get("first_name") and user.get("last_name") and user.get("phone"))
    return schemas.UserOut(
        id=user["id"],
        email=user["email"],
        display_name=user["display_name"],
        first_name=user.get("first_name"),
        last_name=user.get("last_name"),
        phone=user.get("phone"),
        profile_complete=profile_complete,
        egg_balance=user["egg_balance"],
        level=user["level"],
    )


def _course_index(db: Database, course_id: str) -> tuple[list[dict], dict[str, list[dict]], dict[str, list[dict]]]:
    """Batch-fetches every unit/node/question for a course in exactly 3
    queries total, regardless of how many units/nodes it has. The natural
    per-row query pattern (one query per unit, then per node, then per
    question) was fine against local SQLite but unusably slow against a
    remote Atlas cluster — each query pays real network round-trip time,
    and a course can have hundreds of questions."""
    units = list(db.mission_units.find({"course_id": course_id}, batch_size=10000).sort("order_index"))
    unit_ids = [u["id"] for u in units]
    nodes = list(db.mission_nodes.find({"unit_id": {"$in": unit_ids}}, batch_size=10000).sort("order_index")) if unit_ids else []
    nodes_by_unit: dict[str, list[dict]] = {}
    for n in nodes:
        nodes_by_unit.setdefault(n["unit_id"], []).append(n)
    node_ids = [n["id"] for n in nodes]
    questions = list(db.questions.find({"node_id": {"$in": node_ids}}, batch_size=10000).sort("order_index")) if node_ids else []
    questions_by_node: dict[str, list[dict]] = {}
    for q in questions:
        questions_by_node.setdefault(q["node_id"], []).append(q)
    return units, nodes_by_unit, questions_by_node


def _question_ids_for_courses(db: Database, course_ids: list[str]) -> dict[str, list[str]]:
    """Batch-fetches every question id for a set of courses in 3 queries
    total, regardless of how many courses are asked for — the difference
    between a snappy Home screen and a several-second one once there's
    more than one enrolled course, since each query is a real round trip
    to Atlas."""
    result: dict[str, list[str]] = {cid: [] for cid in course_ids}
    if not course_ids:
        return result

    units = list(db.mission_units.find({"course_id": {"$in": course_ids}}, {"id": 1, "course_id": 1}, batch_size=10000))
    unit_ids_by_course: dict[str, list[str]] = {}
    for u in units:
        unit_ids_by_course.setdefault(u["course_id"], []).append(u["id"])
    all_unit_ids = [u["id"] for u in units]

    nodes = list(db.mission_nodes.find({"unit_id": {"$in": all_unit_ids}}, {"id": 1, "unit_id": 1}, batch_size=10000)) if all_unit_ids else []
    node_ids_by_unit: dict[str, list[str]] = {}
    for n in nodes:
        node_ids_by_unit.setdefault(n["unit_id"], []).append(n["id"])
    all_node_ids = [n["id"] for n in nodes]

    questions = list(db.questions.find({"node_id": {"$in": all_node_ids}}, {"id": 1, "node_id": 1}, batch_size=10000)) if all_node_ids else []
    question_ids_by_node: dict[str, list[str]] = {}
    for q in questions:
        question_ids_by_node.setdefault(q["node_id"], []).append(q["id"])

    for course_id, unit_ids in unit_ids_by_course.items():
        ids: list[str] = []
        for unit_id in unit_ids:
            for node_id in node_ids_by_unit.get(unit_id, []):
                ids.extend(question_ids_by_node.get(node_id, []))
        result[course_id] = ids
    return result


def progress_maps(db: Database, user_id: int, question_ids: list[str]) -> tuple[dict[str, dict], set[str], set[str]]:
    """Batch-fetches this user's answers/saved/reported status for a whole
    set of questions in 3 queries total, instead of 3 queries *per
    question*."""
    if not question_ids:
        return {}, set(), set()
    answers = {
        a["question_id"]: a for a in db.node_answers.find({"user_id": user_id, "question_id": {"$in": question_ids}}, batch_size=10000)
    }
    saved_ids = {r["question_id"] for r in db.saved_questions.find({"user_id": user_id, "question_id": {"$in": question_ids}}, batch_size=10000)}
    reported_ids = {
        r["question_id"] for r in db.question_reports.find({"user_id": user_id, "question_id": {"$in": question_ids}}, batch_size=10000)
    }
    return answers, saved_ids, reported_ids


def build_question_out(q: dict, answer: Optional[dict], saved: bool, reported: bool) -> schemas.QuestionOut:
    return schemas.QuestionOut(
        id=q["id"],
        topic_tag=q["topic_tag"],
        prompt=q["prompt"],
        choices=q["choices"],
        correct_index=q["correct_index"],
        step_solution=q["step_solution"],
        answered=answer is not None,
        is_correct=bool(answer and answer.get("is_correct")),
        saved=saved,
        reported=reported,
        selected_index=answer.get("selected_index") if answer else None,
    )


def record_node_answer(
    db: Database,
    user: dict,
    question: dict,
    is_correct: bool,
    selected_index: Optional[int] = None,
) -> bool:
    """Upsert the NodeAnswer for (user, question) and award eggs the first
    time it's answered. Returns True if eggs were just awarded. Shared by
    the normal per-question answer endpoint and the daily egg challenge, so
    both feed the same progress tracking."""
    existing = db.node_answers.find_one({"user_id": user["id"], "question_id": question["id"]})
    if existing is not None:
        db.node_answers.update_one(
            {"_id": existing["_id"]}, {"$set": {"is_correct": is_correct, "selected_index": selected_index}}
        )
        return False

    db.node_answers.insert_one(
        {
            "id": next_id("node_answers"),
            "user_id": user["id"],
            "node_id": question["node_id"],
            "question_id": question["id"],
            "is_correct": is_correct,
            "selected_index": selected_index,
            "answered_at": datetime.datetime.utcnow(),
        }
    )
    db.users.update_one({"id": user["id"]}, {"$inc": {"egg_balance": EGGS_PER_QUESTION}})
    return True


def _episode_out(episode: dict, progress: Optional[dict]) -> schemas.EpisodeOut:
    return schemas.EpisodeOut(
        id=episode["id"],
        title=episode["title"],
        duration_seconds=episode["duration_seconds"],
        youtube_id=episode["youtube_id"],
        completed=bool(progress and progress.get("completed_at") is not None),
        position_seconds=progress["position_seconds"] if progress else 0,
    )


def question_out(db: Database, user_id: int, q: dict) -> schemas.QuestionOut:
    """Single-question lookup (3 queries) — fine for the low-volume call
    sites (one question at a time, or a single topic's ~10-question node).
    Course-wide listings must use the batched path in course_detail_out
    instead, or they'll re-introduce the N+1-against-Atlas problem."""
    answer = db.node_answers.find_one({"user_id": user_id, "question_id": q["id"]})
    saved = db.saved_questions.find_one({"user_id": user_id, "question_id": q["id"]}) is not None
    reported = db.question_reports.find_one({"user_id": user_id, "question_id": q["id"]}) is not None
    return build_question_out(q, answer, saved, reported)


def _chapters_index(db: Database, course_id: str) -> tuple[list[dict], dict[int, list[dict]]]:
    chapters = list(db.chapters.find({"course_id": course_id}, batch_size=10000).sort("order_index"))
    chapter_ids = [c["id"] for c in chapters]
    episodes = list(db.episodes.find({"chapter_id": {"$in": chapter_ids}}, batch_size=10000).sort("order_index")) if chapter_ids else []
    episodes_by_chapter: dict[int, list[dict]] = {}
    for ep in episodes:
        episodes_by_chapter.setdefault(ep["chapter_id"], []).append(ep)
    return chapters, episodes_by_chapter


def _progress_stats_for_courses(db: Database, user_id: int, course_ids: list[str]) -> dict[str, dict]:
    """Batch-computes {course_id: {total_episodes, completed_episodes,
    total_questions, answered_questions}} for any number of courses in a
    fixed ~6 queries total — the shared basis for both the single-course
    and multi-course progress serializers below, so Home (which needs all
    of a user's enrolled courses at once) doesn't pay per-course query
    cost for something it could ask for in one batch."""
    stats = {cid: {"total_episodes": 0, "completed_episodes": 0, "total_questions": 0, "answered_questions": 0} for cid in course_ids}
    if not course_ids:
        return stats

    chapters = list(db.chapters.find({"course_id": {"$in": course_ids}}, {"id": 1, "course_id": 1}, batch_size=10000))
    chapter_ids_by_course: dict[str, list[int]] = {}
    for ch in chapters:
        chapter_ids_by_course.setdefault(ch["course_id"], []).append(ch["id"])
    all_chapter_ids = [ch["id"] for ch in chapters]

    episodes = list(db.episodes.find({"chapter_id": {"$in": all_chapter_ids}}, {"id": 1, "chapter_id": 1}, batch_size=10000)) if all_chapter_ids else []
    episode_ids_by_chapter: dict[int, list[str]] = {}
    for ep in episodes:
        episode_ids_by_chapter.setdefault(ep["chapter_id"], []).append(ep["id"])

    episode_ids_by_course: dict[str, list[str]] = {}
    for course_id, chapter_ids in chapter_ids_by_course.items():
        ids: list[str] = []
        for chapter_id in chapter_ids:
            ids.extend(episode_ids_by_chapter.get(chapter_id, []))
        episode_ids_by_course[course_id] = ids

    all_episode_ids = [eid for ids in episode_ids_by_course.values() for eid in ids]
    completed_episode_ids = (
        {
            p["episode_id"]
            for p in db.episode_progress.find(
                {"user_id": user_id, "episode_id": {"$in": all_episode_ids}, "completed_at": {"$ne": None}}
            )
        }
        if all_episode_ids
        else set()
    )

    # No video content (pure question-bank courses): base progress on how
    # many of its questions have been answered instead.
    videoless_ids = [cid for cid in course_ids if not episode_ids_by_course.get(cid)]
    question_ids_by_course = _question_ids_for_courses(db, videoless_ids)
    all_question_ids = [qid for ids in question_ids_by_course.values() for qid in ids]
    answered_question_ids = (
        {a["question_id"] for a in db.node_answers.find({"user_id": user_id, "question_id": {"$in": all_question_ids}}, {"question_id": 1}, batch_size=10000)}
        if all_question_ids
        else set()
    )

    for cid in course_ids:
        episode_ids = episode_ids_by_course.get(cid, [])
        question_ids = question_ids_by_course.get(cid, [])
        stats[cid] = {
            "total_episodes": len(episode_ids),
            "completed_episodes": sum(1 for eid in episode_ids if eid in completed_episode_ids),
            "total_questions": len(question_ids),
            "answered_questions": sum(1 for qid in question_ids if qid in answered_question_ids),
        }
    return stats


def _course_summary_from_stats(course: dict, enrollment: dict, stats: dict) -> schemas.CourseSummaryOut:
    total_episodes = stats["total_episodes"]
    if total_episodes:
        progress_ratio = stats["completed_episodes"] / total_episodes
    elif stats["total_questions"]:
        progress_ratio = stats["answered_questions"] / stats["total_questions"]
    else:
        progress_ratio = 0.0

    return schemas.CourseSummaryOut(
        id=course["id"],
        code=course["code"],
        title=course["title"],
        instructor=course["instructor"],
        thumb_color_start=course["thumb_color_start"],
        thumb_color_end=course["thumb_color_end"],
        total_hours=course["total_hours"],
        has_eggspace=course["has_eggspace"],
        total_episodes=total_episodes,
        progress=progress_ratio,
        expires_at=enrollment["expires_at"],
        last_episode_id=enrollment.get("last_episode_id"),
    )


def course_summary_out(db: Database, user_id: int, course: dict, enrollment: dict) -> schemas.CourseSummaryOut:
    stats = _progress_stats_for_courses(db, user_id, [course["id"]])[course["id"]]
    return _course_summary_from_stats(course, enrollment, stats)


def course_summaries_out(
    db: Database, user_id: int, courses: list[dict], enrollment_by_course_id: dict[str, dict]
) -> list[schemas.CourseSummaryOut]:
    """Batched form of [course_summary_out] for Home's course list — same
    ~6 queries total regardless of how many enrolled courses there are,
    instead of ~6 *per course*."""
    relevant = [c for c in courses if c["id"] in enrollment_by_course_id]
    stats_by_course = _progress_stats_for_courses(db, user_id, [c["id"] for c in relevant])
    return [_course_summary_from_stats(c, enrollment_by_course_id[c["id"]], stats_by_course[c["id"]]) for c in relevant]


def _content_stats_for_courses(db: Database, course_ids: list[str]) -> dict[str, dict]:
    """Batch-computes {course_id: {subject_count, total_questions}} for the
    catalog listing, in 3 queries total regardless of course count."""
    question_ids_by_course = _question_ids_for_courses(db, course_ids)
    units = list(db.mission_units.find({"course_id": {"$in": course_ids}}, {"course_id": 1}, batch_size=10000)) if course_ids else []
    subject_counts: dict[str, int] = {}
    for u in units:
        subject_counts[u["course_id"]] = subject_counts.get(u["course_id"], 0) + 1
    return {
        cid: {"subject_count": subject_counts.get(cid, 0), "total_questions": len(question_ids_by_course.get(cid, []))}
        for cid in course_ids
    }


def course_catalog_entries_out(db: Database, courses: list[dict], enrolled_ids: set[str]) -> list[schemas.CourseCatalogOut]:
    stats_by_course = _content_stats_for_courses(db, [c["id"] for c in courses])
    return [
        schemas.CourseCatalogOut(
            id=course["id"],
            code=course["code"],
            title=course["title"],
            instructor=course["instructor"],
            thumb_color_start=course["thumb_color_start"],
            thumb_color_end=course["thumb_color_end"],
            subject_count=stats_by_course[course["id"]]["subject_count"],
            total_questions=stats_by_course[course["id"]]["total_questions"],
            has_eggspace=course["has_eggspace"],
            enrolled=course["id"] in enrolled_ids,
        )
        for course in courses
    ]


def course_detail_out(db: Database, user_id: int, course: dict, enrollment: dict) -> schemas.CourseDetailOut:
    """Fetches chapters/units/nodes/questions exactly once each (~7 queries
    total) and derives both the summary stats and the full per-question
    breakdown from that same data — course_summary_out fetches the same
    unit/node/question tree via a separate call, so calling it here would
    silently double every one of those round trips."""
    chapters, episodes_by_chapter = _chapters_index(db, course["id"])
    all_episodes = [ep for eps in episodes_by_chapter.values() for ep in eps]
    total_episodes = len(all_episodes)
    if total_episodes:
        episode_ids = [ep["id"] for ep in all_episodes]
        progress_by_episode = {p["episode_id"]: p for p in db.episode_progress.find({"user_id": user_id, "episode_id": {"$in": episode_ids}}, batch_size=10000)}
        completed_episodes = sum(1 for p in progress_by_episode.values() if p.get("completed_at") is not None)
    else:
        progress_by_episode = {}
        completed_episodes = 0

    chapters_out = [
        schemas.ChapterOut(
            title=chapter["title"],
            episodes=[
                _episode_out(ep, progress_by_episode.get(ep["id"]))
                for ep in episodes_by_chapter.get(chapter["id"], [])
            ],
        )
        for chapter in chapters
    ]

    units, nodes_by_unit, questions_by_node = _course_index(db, course["id"])
    all_question_ids = [q["id"] for qs in questions_by_node.values() for q in qs]
    answers, saved_ids, reported_ids = progress_maps(db, user_id, all_question_ids)

    if total_episodes:
        course_progress = completed_episodes / total_episodes
    elif all_question_ids:
        course_progress = sum(1 for qid in all_question_ids if qid in answers) / len(all_question_ids)
    else:
        course_progress = 0.0

    mission_units_out = []
    for unit in units:
        nodes = nodes_by_unit.get(unit["id"], [])
        questions_out = []
        unit_question_ids = []
        for node in nodes:
            for q in questions_by_node.get(node["id"], []):
                answer = answers.get(q["id"])
                questions_out.append(build_question_out(q, answer, q["id"] in saved_ids, q["id"] in reported_ids))
                unit_question_ids.append(q["id"])

        answered_count = sum(1 for qo in questions_out if qo.answered)
        progress = answered_count / len(questions_out) if questions_out else 0.0
        answered_ats = [answers[qid]["answered_at"] for qid in unit_question_ids if qid in answers]
        last_activity_at = max(answered_ats) if answered_ats else None

        mission_units_out.append(
            schemas.MissionUnitOut(
                id=unit["id"],
                title=unit["title"],
                progress=progress,
                total_questions=len(questions_out),
                last_activity_at=last_activity_at,
                questions=questions_out,
            )
        )

    return schemas.CourseDetailOut(
        id=course["id"],
        code=course["code"],
        title=course["title"],
        instructor=course["instructor"],
        thumb_color_start=course["thumb_color_start"],
        thumb_color_end=course["thumb_color_end"],
        total_hours=course["total_hours"],
        has_eggspace=course["has_eggspace"],
        total_episodes=total_episodes,
        progress=course_progress,
        expires_at=enrollment["expires_at"],
        last_episode_id=enrollment.get("last_episode_id"),
        chapters=chapters_out,
        mission_units=mission_units_out,
    )
