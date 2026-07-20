import random
from typing import List

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

import auth
import models
import schemas
from database import get_db

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
def list_messages(
    db: Session = Depends(get_db), current_user: models.User = Depends(auth.get_current_user)
):
    return (
        db.query(models.ChatMessage)
        .filter(models.ChatMessage.user_id == current_user.id)
        .order_by(models.ChatMessage.created_at)
        .all()
    )


@router.post("", response_model=schemas.ChatSendResponse, status_code=201)
def send_message(
    payload: schemas.ChatSendRequest,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.get_current_user),
):
    user_message = models.ChatMessage(user_id=current_user.id, role="user", content=payload.content)
    db.add(user_message)
    db.commit()
    db.refresh(user_message)

    assistant_message = models.ChatMessage(
        user_id=current_user.id, role="assistant", content=random.choice(MOCK_REPLIES)
    )
    db.add(assistant_message)
    db.commit()
    db.refresh(assistant_message)

    return schemas.ChatSendResponse(user_message=user_message, assistant_message=assistant_message)
