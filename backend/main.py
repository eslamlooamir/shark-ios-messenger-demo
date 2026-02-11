import os
import json
from datetime import datetime
from typing import Set, Literal, Optional, List

from dotenv import load_dotenv
from fastapi import FastAPI, Depends, WebSocket, WebSocketDisconnect, HTTPException
from pydantic import BaseModel
from sqlalchemy import (
    create_engine, Integer, String, Boolean, ForeignKey, DateTime, Text
)
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship, sessionmaker, Session

load_dotenv()
DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./shark.db")

engine_kwargs = {}
if DATABASE_URL.startswith("sqlite"):
    engine_kwargs["connect_args"] = {"check_same_thread": False}
else:
    engine_kwargs["pool_pre_ping"] = True

engine = create_engine(DATABASE_URL, **engine_kwargs)
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)


# ---------------- DB ----------------
class Base(DeclarativeBase):
    pass

class Contact(Base):
    __tablename__ = "contacts"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(80), index=True)
    username: Mapped[str] = mapped_column(String(80), unique=True, index=True)
    verified: Mapped[bool] = mapped_column(Boolean, default=False)

class Chat(Base):
    __tablename__ = "chats"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    kind: Mapped[str] = mapped_column(String(16))  # direct/group/channel
    title: Mapped[str] = mapped_column(String(120), index=True)
    verified: Mapped[bool] = mapped_column(Boolean, default=False)
    last_message: Mapped[str] = mapped_column(String(200), default="")
    last_time: Mapped[str] = mapped_column(String(32), default="Now")
    unread: Mapped[int] = mapped_column(Integer, default=0)

    messages: Mapped[List["Message"]] = relationship(back_populates="chat", cascade="all, delete-orphan")

class Message(Base):
    __tablename__ = "messages"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    chat_id: Mapped[int] = mapped_column(ForeignKey("chats.id", ondelete="CASCADE"), index=True)
    mine: Mapped[bool] = mapped_column(Boolean, default=False)
    text: Mapped[str] = mapped_column(Text)
    time: Mapped[str] = mapped_column(String(32), default="Now")
    status: Mapped[str] = mapped_column(String(16), default="Sent")  # Sent/Delivered/Read
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    chat: Mapped["Chat"] = relationship(back_populates="messages")

class CallLog(Base):
    __tablename__ = "call_logs"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(80))
    type: Mapped[str] = mapped_column(String(8))        # voice/video
    direction: Mapped[str] = mapped_column(String(12))  # incoming/outgoing/missed
    time: Mapped[str] = mapped_column(String(64))       # "Today • 22:10"

class UserSettings(Base):
    __tablename__ = "user_settings"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    screen_lock: Mapped[bool] = mapped_column(Boolean, default=True)
    read_receipts: Mapped[bool] = mapped_column(Boolean, default=True)
    link_preview: Mapped[bool] = mapped_column(Boolean, default=False)
    safety_alerts: Mapped[bool] = mapped_column(Boolean, default=True)

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

# ---------------- Schemas ----------------
ChatKind = Literal["direct", "group", "channel"]
CallType = Literal["voice", "video"]
CallDirection = Literal["incoming", "outgoing", "missed"]

class ContactOut(BaseModel):
    id: int
    name: str
    username: str
    verified: bool

class ChatOut(BaseModel):
    id: int
    kind: ChatKind
    title: str
    last: str
    time: str
    unread: int
    verified: bool

class ChatCreate(BaseModel):
    kind: ChatKind
    title: str
    verified: bool = False

class MessageOut(BaseModel):
    id: int
    chat_id: int
    mine: bool
    text: str
    time: str
    status: str

class MessageCreate(BaseModel):
    mine: bool = True
    text: str

class CallLogOut(BaseModel):
    id: int
    name: str
    type: CallType
    direction: CallDirection
    time: str

class CallLogCreate(BaseModel):
    name: str
    type: CallType
    direction: CallDirection
    time: str

class SettingsOut(BaseModel):
    screen_lock: bool
    read_receipts: bool
    link_preview: bool
    safety_alerts: bool

class SettingsUpdate(BaseModel):
    screen_lock: bool
    read_receipts: bool
    link_preview: bool
    safety_alerts: bool

# WebSocket payload
class WSMessage(BaseModel):
    type: str  # "message"
    chat_id: int
    id: int
    mine: bool
    text: str
    time: str
    status: str

# ---------------- WebSocket Manager ----------------
class ConnectionManager:
    def __init__(self) -> None:
        self.active: Set[WebSocket] = set()

    async def connect(self, ws: WebSocket):
        await ws.accept()
        self.active.add(ws)

    def disconnect(self, ws: WebSocket):
        self.active.discard(ws)

    async def broadcast(self, payload: dict):
        dead = []
        data = json.dumps(payload)
        for ws in list(self.active):
            try:
                await ws.send_text(data)
            except Exception:
                dead.append(ws)
        for ws in dead:
            self.disconnect(ws)

manager = ConnectionManager()

# ---------------- App ----------------
app = FastAPI(title="Shark Backend", version="0.1.0")

@app.on_event("startup")
def startup():
    Base.metadata.create_all(bind=engine)

    # seed
    with SessionLocal() as db:
        if db.query(Contact).count() == 0:
            db.add_all([
                Contact(name="Sara", username="@sara", verified=True),
                Contact(name="Mehdi", username="@mehdi", verified=False),
                Contact(name="Niloofar", username="@niloofar", verified=True),
                Contact(name="Arman", username="@arman", verified=False),
                Contact(name="Shahin", username="@shahin", verified=False),
            ])
            db.commit()

        if db.query(Chat).count() == 0:
            chats = [
                Chat(kind="direct", title="Sara", verified=True,  last_message="Ok, send it here.", last_time="22:41", unread=2),
                Chat(kind="group", title="Shark Team", verified=True, last_message="Standup 10:00", last_time="21:08", unread=0),
                Chat(kind="channel", title="Shark Updates", verified=False, last_message="New build is live.", last_time="19:30", unread=1),
                Chat(kind="direct", title="Mehdi", verified=False, last_message="Call me when ready.", last_time="18:07", unread=0),
            ]
            db.add_all(chats)
            db.commit()

            sara = db.query(Chat).filter(Chat.title == "Sara").first()
            if sara:
                db.add_all([
                    Message(chat_id=sara.id, mine=False, text="Hi 👋", time="21:30", status=""),
                    Message(chat_id=sara.id, mine=True,  text="Hey. Shark looks clean.", time="21:31", status="Read"),
                    Message(chat_id=sara.id, mine=False, text="Make buttons glass & oval.", time="21:32", status=""),
                    Message(chat_id=sara.id, mine=True,  text="Done ✅", time="21:33", status="Delivered"),
                ])
                db.commit()

        if db.query(CallLog).count() == 0:
            db.add_all([
                CallLog(name="Sara", type="video", direction="incoming", time="Today • 22:10"),
                CallLog(name="Mehdi", type="voice", direction="outgoing", time="Today • 19:55"),
                CallLog(name="Shark Team", type="voice", direction="missed", time="Yesterday • 12:03"),
            ])
            db.commit()

        if db.query(UserSettings).count() == 0:
            db.add(UserSettings())
            db.commit()

# -------- Contacts --------
@app.get("/contacts", response_model=list[ContactOut])
def get_contacts(q: Optional[str] = None, db: Session = Depends(get_db)):
    query = db.query(Contact)
    if q:
        query = query.filter((Contact.name.ilike(f"%{q}%")) | (Contact.username.ilike(f"%{q}%")))
    rows = query.order_by(Contact.name.asc()).all()
    return [ContactOut(id=r.id, name=r.name, username=r.username, verified=r.verified) for r in rows]

# -------- Chats --------
@app.get("/chats", response_model=list[ChatOut])
def get_chats(db: Session = Depends(get_db)):
    rows = db.query(Chat).order_by(Chat.id.desc()).all()
    return [ChatOut(id=r.id, kind=r.kind, title=r.title, last=r.last_message, time=r.last_time, unread=r.unread, verified=r.verified) for r in rows]

@app.post("/chats", response_model=ChatOut)
def create_chat(payload: ChatCreate, db: Session = Depends(get_db)):
    title = payload.title.strip()
    if not title:
        raise HTTPException(status_code=400, detail="title required")

    existing = db.query(Chat).filter(Chat.kind == payload.kind, Chat.title.ilike(title)).first()
    if existing:
        return ChatOut(id=existing.id, kind=existing.kind, title=existing.title,
                       last=existing.last_message, time=existing.last_time, unread=existing.unread, verified=existing.verified)

    chat = Chat(kind=payload.kind, title=title, verified=payload.verified, last_message="Chat started.", last_time="Now", unread=0)
    db.add(chat)
    db.commit()
    db.refresh(chat)

    return ChatOut(id=chat.id, kind=chat.kind, title=chat.title,
                   last=chat.last_message, time=chat.last_time, unread=chat.unread, verified=chat.verified)

# -------- Messages --------
@app.get("/chats/{chat_id}/messages", response_model=list[MessageOut])
def get_messages(chat_id: int, db: Session = Depends(get_db)):
    chat = db.query(Chat).filter(Chat.id == chat_id).first()
    if not chat:
        raise HTTPException(status_code=404, detail="chat not found")

    rows = db.query(Message).filter(Message.chat_id == chat_id).order_by(Message.id.asc()).all()
    return [MessageOut(id=r.id, chat_id=r.chat_id, mine=r.mine, text=r.text, time=r.time, status=r.status) for r in rows]

@app.post("/chats/{chat_id}/messages", response_model=MessageOut)
async def send_message(chat_id: int, payload: MessageCreate, db: Session = Depends(get_db)):
    chat = db.query(Chat).filter(Chat.id == chat_id).first()
    if not chat:
        raise HTTPException(status_code=404, detail="chat not found")

    text = payload.text.strip()
    if not text:
        raise HTTPException(status_code=400, detail="text required")

    now = datetime.now().strftime("%H:%M")
    msg = Message(chat_id=chat_id, mine=payload.mine, text=text, time=now, status="Sent")
    db.add(msg)

    # update chat preview
    chat.last_message = text[:200]
    chat.last_time = now
    db.commit()
    db.refresh(msg)

    # broadcast to all WS clients (MVP)
    await manager.broadcast({
        "type": "message",
        "chat_id": chat_id,
        "id": msg.id,
        "mine": msg.mine,
        "text": msg.text,
        "time": msg.time,
        "status": "Delivered"
    })

    return MessageOut(id=msg.id, chat_id=msg.chat_id, mine=msg.mine, text=msg.text, time=msg.time, status=msg.status)

# -------- Calls --------
@app.get("/calls/logs", response_model=list[CallLogOut])
def get_call_logs(db: Session = Depends(get_db)):
    rows = db.query(CallLog).order_by(CallLog.id.desc()).all()
    return [CallLogOut(id=r.id, name=r.name, type=r.type, direction=r.direction, time=r.time) for r in rows]

@app.post("/calls/logs", response_model=CallLogOut)
def add_call_log(payload: CallLogCreate, db: Session = Depends(get_db)):
    row = CallLog(name=payload.name, type=payload.type, direction=payload.direction, time=payload.time)
    db.add(row)
    db.commit()
    db.refresh(row)
    return CallLogOut(id=row.id, name=row.name, type=row.type, direction=row.direction, time=row.time)

# -------- Settings --------
@app.get("/settings", response_model=SettingsOut)
def get_settings(db: Session = Depends(get_db)):
    s = db.query(UserSettings).first()
    return SettingsOut(
        screen_lock=s.screen_lock,
        read_receipts=s.read_receipts,
        link_preview=s.link_preview,
        safety_alerts=s.safety_alerts
    )

@app.put("/settings", response_model=SettingsOut)
def update_settings(payload: SettingsUpdate, db: Session = Depends(get_db)):
    s = db.query(UserSettings).first()
    s.screen_lock = payload.screen_lock
    s.read_receipts = payload.read_receipts
    s.link_preview = payload.link_preview
    s.safety_alerts = payload.safety_alerts
    db.commit()
    return SettingsOut(
        screen_lock=s.screen_lock,
        read_receipts=s.read_receipts,
        link_preview=s.link_preview,
        safety_alerts=s.safety_alerts
    )

# -------- WebSocket --------
@app.websocket("/ws")
async def websocket_endpoint(ws: WebSocket):
    await manager.connect(ws)
    try:
        while True:
            # MVP: we don't require client -> server messages over WS
            # (sending is done via REST)
            _ = await ws.receive_text()
    except WebSocketDisconnect:
        manager.disconnect(ws)
