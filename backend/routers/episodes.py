import datetime

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

import auth
import models
import schemas
from database import get_db

router = APIRouter(prefix="/episodes", tags=["episodes"])


def _get_episode_or_404(db: Session, episode_id: str) -> models.Episode:
    episode = db.query(models.Episode).filter(models.Episode.id == episode_id).first()
    if episode is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Episode not found")
    return episode


def _get_or_create_progress(db: Session, user_id: int, episode_id: str) -> models.EpisodeProgress:
    progress = (
        db.query(models.EpisodeProgress)
        .filter(
            models.EpisodeProgress.user_id == user_id,
            models.EpisodeProgress.episode_id == episode_id,
        )
        .first()
    )
    if progress is None:
        progress = models.EpisodeProgress(user_id=user_id, episode_id=episode_id, position_seconds=0)
        db.add(progress)
    return progress


def _touch_last_episode(db: Session, user_id: int, episode: models.Episode) -> None:
    course_id = episode.chapter.course_id
    enrollment = (
        db.query(models.Enrollment)
        .filter(models.Enrollment.user_id == user_id, models.Enrollment.course_id == course_id)
        .first()
    )
    if enrollment is not None:
        enrollment.last_episode_id = episode.id


@router.post("/{episode_id}/progress", status_code=status.HTTP_204_NO_CONTENT)
def update_progress(
    episode_id: str,
    payload: schemas.PositionUpdateRequest,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user),
):
    episode = _get_episode_or_404(db, episode_id)
    progress = _get_or_create_progress(db, current_user.id, episode_id)
    progress.position_seconds = payload.position_seconds
    progress.updated_at = datetime.datetime.utcnow()
    _touch_last_episode(db, current_user.id, episode)
    db.commit()


@router.post("/{episode_id}/complete", status_code=status.HTTP_204_NO_CONTENT)
def complete_episode(
    episode_id: str,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user),
):
    episode = _get_episode_or_404(db, episode_id)
    progress = _get_or_create_progress(db, current_user.id, episode_id)
    progress.completed_at = datetime.datetime.utcnow()
    _touch_last_episode(db, current_user.id, episode)
    db.commit()
