import datetime
import os

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from google.auth.transport import requests as google_requests
from google.oauth2 import id_token as google_id_token
from pymongo.database import Database

from database import get_db

# Dev-only secret. Rotate and load from env before any real deployment.
SECRET_KEY = "v-learn-dev-secret-change-me"
ALGORITHM = "HS256"
TOKEN_EXPIRE_DAYS = 7

# Public OAuth client id (safe to embed — this is not the client secret,
# which is never used by this app since sign-in verifies Google ID tokens
# directly instead of doing a server-side authorization-code exchange).
# Must match the client id the Flutter app requests tokens with, or every
# sign-in fails `aud` verification below.
GOOGLE_CLIENT_ID = os.environ["GOOGLE_CLIENT_ID"]

bearer_scheme = HTTPBearer()
_google_request = google_requests.Request()


def verify_google_id_token(token: str) -> dict:
    try:
        return google_id_token.verify_oauth2_token(token, _google_request, GOOGLE_CLIENT_ID)
    except ValueError:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid Google token")


def create_access_token(user_id: int) -> str:
    payload = {
        "sub": str(user_id),
        "exp": datetime.datetime.utcnow() + datetime.timedelta(days=TOKEN_EXPIRE_DAYS),
    }
    return jwt.encode(payload, SECRET_KEY, algorithm=ALGORITHM)


def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
    db: Database = Depends(get_db),
) -> dict:
    unauthorized = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Invalid or expired token",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(credentials.credentials, SECRET_KEY, algorithms=[ALGORITHM])
        user_id = int(payload.get("sub"))
    except (jwt.PyJWTError, TypeError, ValueError):
        raise unauthorized

    user = db.users.find_one({"id": user_id})
    if user is None:
        raise unauthorized
    return user
