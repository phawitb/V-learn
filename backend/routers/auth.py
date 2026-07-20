from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

import auth
import models
import schemas
from database import get_db

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/google", response_model=schemas.TokenResponse)
def google_login(payload: schemas.GoogleAuthRequest, db: Session = Depends(get_db)):
    claims = auth.verify_google_id_token(payload.id_token)
    google_sub = claims["sub"]
    email = claims.get("email", "")
    given_name = claims.get("given_name", "")
    family_name = claims.get("family_name", "")

    user = db.query(models.User).filter(models.User.google_sub == google_sub).first()
    if user is None:
        # A Google account previously seen via a different sign-in path (or
        # seeded some other way) — link it by email instead of duplicating.
        user = db.query(models.User).filter(models.User.email == email).first()

    if user is None:
        user = models.User(
            email=email,
            google_sub=google_sub,
            display_name=f"{given_name} {family_name}".strip() or email.split("@")[0],
        )
        db.add(user)
        db.commit()
        db.refresh(user)
    elif user.google_sub is None:
        user.google_sub = google_sub
        db.commit()
        db.refresh(user)

    token = auth.create_access_token(user.id)
    return schemas.TokenResponse(access_token=token, user=schemas.UserOut.model_validate(user))


@router.post("/profile", response_model=schemas.UserOut)
def complete_profile(
    payload: schemas.ProfileCompleteRequest,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user),
):
    current_user.first_name = payload.first_name.strip()
    current_user.last_name = payload.last_name.strip()
    current_user.phone = payload.phone.strip()
    current_user.display_name = f"{current_user.first_name} {current_user.last_name}".strip()
    db.commit()
    db.refresh(current_user)
    return current_user


@router.get("/me", response_model=schemas.UserOut)
def me(current_user: models.User = Depends(auth.get_current_user)):
    return current_user
