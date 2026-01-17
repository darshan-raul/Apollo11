from fastapi import FastAPI, Depends, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.orm import Session
from sqlalchemy.exc import IntegrityError
from typing import List
import requests
import os
from . import models, database
from .models import User, Stage, UserStageProgress

app = FastAPI(title="Apollo 11 Core API")

# CORS
origins = ["*"] # Adjust in production
app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Create tables (for simplicity, though migrations are preferred)
# models.Base.metadata.create_all(bind=database.engine)

QUIZ_SERVICE_URL = os.getenv("QUIZ_SERVICE_URL", "http://quiz-service:8080")
NOTIFICATION_SERVICE_URL = os.getenv("NOTIFICATION_SERVICE_URL", "http://notification-service:8000")
PAYMENT_SERVICE_URL = os.getenv("PAYMENT_SERVICE_URL", "http://payment-api:8080")

def get_current_user(db: Session = Depends(database.get_db)) -> User:
    # Dummy user for dev since Keycloak is removed
    email = "commander@apollo11.com"
    keycloak_id = "dummy-commander-id" 
    user = db.query(models.User).filter(models.User.keycloak_id == keycloak_id).first()
    if not user:
        try:
            user = models.User(keycloak_id=keycloak_id, email=email)
            db.add(user)
            db.commit()
            db.refresh(user)
        except IntegrityError:
            db.rollback()
            user = db.query(models.User).filter(models.User.keycloak_id == keycloak_id).first()
    return user

from fastapi import Response, status

@app.get("/health/live")
def health_live():
    return {"status": "alive"}

@app.get("/health/ready")
def health_ready(response: Response, db: Session = Depends(database.get_db)):
    try:
        from sqlalchemy import text
        db.execute(text("SELECT 1"))
        return {"status": "ready"}
    except Exception as e:
        response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE
        return {"status": "not ready", "error": str(e)}

@app.get("/me", response_model=models.UserResponse)
def get_me(user: User = Depends(get_current_user)):
    return user

@app.get("/stages", response_model=List[models.StageResponse])
def get_stages(db: Session = Depends(database.get_db), user: User = Depends(get_current_user)):
    stages = db.query(Stage).order_by(Stage.order).all()
    return stages

@app.get("/progress", response_model=List[models.ProgressResponse])
def get_progress(db: Session = Depends(database.get_db), user: User = Depends(get_current_user)):
    progress = db.query(UserStageProgress).filter(UserStageProgress.user_id == user.id).all()
    return progress

@app.post("/stages/{stage_id}/start")
def start_stage(stage_id: int, db: Session = Depends(database.get_db), user: User = Depends(get_current_user)):
    # Unlock stage if possible or mark in progress
    # Logic: Can only start if previous stage completed?
    # For now, simplistic implementation
    prog = db.query(UserStageProgress).filter(UserStageProgress.user_id == user.id, UserStageProgress.stage_id == stage_id).first()
    if not prog:
        prog = UserStageProgress(user_id=user.id, stage_id=stage_id, status=models.StageStatus.in_progress)
        db.add(prog)
    else:
        prog.status = models.StageStatus.in_progress
    db.commit()
    return {"status": "started"}

@app.post("/stages/{stage_id}/complete")
def complete_stage(stage_id: int, db: Session = Depends(database.get_db), user: User = Depends(get_current_user)):
    prog = db.query(UserStageProgress).filter(UserStageProgress.user_id == user.id, UserStageProgress.stage_id == stage_id).first()
    if not prog:
         prog = UserStageProgress(user_id=user.id, stage_id=stage_id, status=models.StageStatus.completed)
         db.add(prog)
    else:
        prog.status = models.StageStatus.completed
    db.commit()
    
    # Unlock next stage?
    # ... logic ...
    
    return {"status": "completed"}

@app.post("/quiz/{stage_id}/start")
def start_quiz(stage_id: int, user: User = Depends(get_current_user)):
    # Call Quiz Service to start quiz
    try:
        resp = requests.post(f"{QUIZ_SERVICE_URL}/quiz/start", json={"user_id": str(user.id), "stage_id": stage_id})
        resp.raise_for_status()
        return resp.json()
    except requests.RequestException as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/quiz/{stage_id}/submit")
def submit_quiz(stage_id: int, answers: dict, user: User = Depends(get_current_user)):
    # Call Quiz Service to evaluate
    try:
        payload = {
            "user_id": str(user.id), 
            "stage_id": stage_id,
            "answers": answers # Expected format depends on Quiz Service
        }
        resp = requests.post(f"{QUIZ_SERVICE_URL}/quiz/evaluate", json=payload)
        resp.raise_for_status()
        result = resp.json()
        
        return result
    except requests.RequestException as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/quiz/results")
def get_quiz_results(user: User = Depends(get_current_user)):
    try:
         resp = requests.get(f"{QUIZ_SERVICE_URL}/quiz/results/{user.id}")
         resp.raise_for_status()
         return resp.json()
    except requests.RequestException as e:
        raise HTTPException(status_code=500, detail=str(e))
