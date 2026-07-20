from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

import seed
from database import ensure_indexes, get_db
from routers import auth, chat, courses, daily_egg, episodes, mistakes, mock_exam, questions

_db = get_db()
ensure_indexes()
seed.seed_if_empty(_db)
seed.seed_mock_exams(_db)

app = FastAPI(title="V-Learn API")

# Dev-only: wide open CORS so `flutter run -d chrome` on any local port can
# call this API. Tighten before shipping anywhere real.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router)
app.include_router(courses.router)
app.include_router(episodes.router)
app.include_router(mistakes.router)
app.include_router(chat.router)
app.include_router(questions.router)
app.include_router(daily_egg.router)
app.include_router(mock_exam.router)


@app.get("/health")
def health():
    return {"status": "ok"}
