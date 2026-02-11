# 🦈 Shark – iOS Messenger Demo

Shark is a modern iOS messaging demo app built with **SwiftUI** and a lightweight **FastAPI backend**.

This project demonstrates production-level UI design, real-time messaging architecture, and clean project structure.

---

## ✨ Features

- Modern dark blue UI theme
- Glass-style oval buttons
- Chat list & chat detail screen
- Real-time messaging (WebSocket)
- Calls screen (voice & video logs)
- Trends (future expandable feature)
- Settings with user preferences
- FastAPI backend with SQLite
- REST + WebSocket integration

---

## 📱 Screenshots

### Chat List
![Chat List](assets/screenshots/chat_list.png)

### Chat Detail
![Chat Detail](assets/screenshots/chat_detail.png)

---

## 🛠 Tech Stack

### iOS
- Swift
- SwiftUI
- MVVM architecture

### Backend
- FastAPI
- SQLAlchemy
- SQLite
- WebSocket
- Uvicorn

---

## 🚀 Running Backend

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn main:app --reload
