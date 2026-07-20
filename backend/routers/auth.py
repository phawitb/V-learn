from fastapi import APIRouter, Depends
from pymongo.database import Database

import auth
import schemas
import serializers
from database import get_db, next_id

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/google", response_model=schemas.TokenResponse)
def google_login(payload: schemas.GoogleAuthRequest, db: Database = Depends(get_db)):
    claims = auth.verify_google_id_token(payload.id_token)
    google_sub = claims["sub"]
    email = claims.get("email", "")
    given_name = claims.get("given_name", "")
    family_name = claims.get("family_name", "")

    user = db.users.find_one({"google_sub": google_sub})
    if user is None:
        # A Google account previously seen via a different sign-in path (or
        # seeded some other way) — link it by email instead of duplicating.
        user = db.users.find_one({"email": email})

    if user is None:
        user = {
            "id": next_id("users"),
            "email": email,
            "google_sub": google_sub,
            "first_name": None,
            "last_name": None,
            "phone": None,
            "display_name": f"{given_name} {family_name}".strip() or email.split("@")[0],
            "egg_balance": 100,
            "level": 1,
        }
        db.users.insert_one(user)
    elif user.get("google_sub") is None:
        db.users.update_one({"id": user["id"]}, {"$set": {"google_sub": google_sub}})
        user["google_sub"] = google_sub

    token = auth.create_access_token(user["id"])
    return schemas.TokenResponse(access_token=token, user=serializers.user_out(user))


@router.post("/profile", response_model=schemas.UserOut)
def complete_profile(
    payload: schemas.ProfileCompleteRequest,
    db: Database = Depends(get_db),
    current_user: dict = Depends(auth.get_current_user),
):
    first_name = payload.first_name.strip()
    last_name = payload.last_name.strip()
    phone = payload.phone.strip()
    display_name = f"{first_name} {last_name}".strip()
    db.users.update_one(
        {"id": current_user["id"]},
        {"$set": {"first_name": first_name, "last_name": last_name, "phone": phone, "display_name": display_name}},
    )
    current_user.update(first_name=first_name, last_name=last_name, phone=phone, display_name=display_name)
    return serializers.user_out(current_user)


@router.get("/me", response_model=schemas.UserOut)
def me(current_user: dict = Depends(auth.get_current_user)):
    return serializers.user_out(current_user)
