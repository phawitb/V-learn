import datetime
import random
from typing import List

from fastapi import APIRouter, Depends
from pymongo.database import Database

import auth
import schemas
from database import get_db, next_id

router = APIRouter(prefix="/chat", tags=["chat"])

# DEV ONLY: canned replies standing in for a real LLM. Swap this for an
# actual model call (e.g. the Anthropic API) when going live — see
# CLAUDE.md/task notes for the mock-vs-real decision.
MOCK_REPLIES = [
    "ขอบคุณสำหรับคำถามนะครับ ตอนนี้ยังเป็นคำตอบจำลอง (mock) อยู่ — ลองอ่าน Step Solution ในข้อนั้นๆ ประกอบดูนะครับ",
    "เข้าใจคำถามแล้วครับ ลองทบทวนจากคำอธิบายในเฉลยของข้อนั้นก่อน ถ้ายังไม่ชัดเจนถามระบุรายละเอียดเพิ่มได้เลยครับ",
    "เป็นคำถามที่ดีมากครับ เดี๋ยวเวอร์ชันจริงผู้ช่วย AI จะอธิบายละเอียดกว่านี้ ระหว่างนี้ลองดูวิธีคิดใน Step Solution ไปพลางๆ ก่อนนะครับ",
]


@router.get("", response_model=List[schemas.ChatMessageOut])
def list_messages(db: Database = Depends(get_db), current_user: dict = Depends(auth.get_current_user)):
    return list(db.chat_messages.find({"user_id": current_user["id"]}, batch_size=10000).sort("created_at"))


@router.post("", response_model=schemas.ChatSendResponse, status_code=201)
def send_message(
    payload: schemas.ChatSendRequest,
    db: Database = Depends(get_db),
    current_user: dict = Depends(auth.get_current_user),
):
    user_message = {
        "id": next_id("chat_messages"),
        "user_id": current_user["id"],
        "role": "user",
        "content": payload.content,
        "created_at": datetime.datetime.utcnow(),
    }
    db.chat_messages.insert_one(user_message)

    assistant_message = {
        "id": next_id("chat_messages"),
        "user_id": current_user["id"],
        "role": "assistant",
        "content": random.choice(MOCK_REPLIES),
        "created_at": datetime.datetime.utcnow(),
    }
    db.chat_messages.insert_one(assistant_message)

    return schemas.ChatSendResponse(user_message=user_message, assistant_message=assistant_message)
