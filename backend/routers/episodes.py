import datetime

from fastapi import APIRouter, Depends, HTTPException, status
from pymongo.database import Database

import auth
import schemas
from database import get_db, next_id

router = APIRouter(prefix="/episodes", tags=["episodes"])


def _get_episode_or_404(db: Database, episode_id: str) -> dict:
    episode = db.episodes.find_one({"id": episode_id})
    if episode is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Episode not found")
    return episode


def _get_or_create_progress(db: Database, user_id: int, episode_id: str) -> dict:
    progress = db.episode_progress.find_one({"user_id": user_id, "episode_id": episode_id})
    if progress is None:
        progress = {
            "id": next_id("episode_progress"),
            "user_id": user_id,
            "episode_id": episode_id,
            "position_seconds": 0,
            "completed_at": None,
            "updated_at": datetime.datetime.utcnow(),
        }
        db.episode_progress.insert_one(progress)
    return progress


def _touch_last_episode(db: Database, user_id: int, episode: dict) -> None:
    chapter = db.chapters.find_one({"id": episode["chapter_id"]})
    if chapter is None:
        return
    db.enrollments.update_one(
        {"user_id": user_id, "course_id": chapter["course_id"]},
        {"$set": {"last_episode_id": episode["id"]}},
    )


@router.post("/{episode_id}/progress", status_code=status.HTTP_204_NO_CONTENT)
def update_progress(
    episode_id: str,
    payload: schemas.PositionUpdateRequest,
    db: Database = Depends(get_db),
    current_user: dict = Depends(auth.get_current_user),
):
    episode = _get_episode_or_404(db, episode_id)
    progress = _get_or_create_progress(db, current_user["id"], episode_id)
    db.episode_progress.update_one(
        {"_id": progress["_id"]},
        {"$set": {"position_seconds": payload.position_seconds, "updated_at": datetime.datetime.utcnow()}},
    )
    _touch_last_episode(db, current_user["id"], episode)


@router.post("/{episode_id}/complete", status_code=status.HTTP_204_NO_CONTENT)
def complete_episode(
    episode_id: str,
    db: Database = Depends(get_db),
    current_user: dict = Depends(auth.get_current_user),
):
    episode = _get_episode_or_404(db, episode_id)
    progress = _get_or_create_progress(db, current_user["id"], episode_id)
    db.episode_progress.update_one({"_id": progress["_id"]}, {"$set": {"completed_at": datetime.datetime.utcnow()}})
    _touch_last_episode(db, current_user["id"], episode)
