from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="Notification Service")

class NotificationRequest(BaseModel):
    user_id: str
    message: str
    channel: str = "email"

@app.get("/health/live")
def health_live():
    return {"status": "alive"}

@app.get("/health/ready")
def health_ready():
    return {"status": "ready"}

@app.post("/notify")
def send_notification(notification: NotificationRequest):
    # Simulation of sending notification
    logger.info(f"Sending {notification.channel} to user {notification.user_id}: {notification.message}")
    return {"status": "sent", "details": notification.dict()}
