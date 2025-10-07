"""
Apollo 11 Astronaut Onboarding Frontend
FastAPI application with modern UI
"""
import os
import sys
from pathlib import Path
from fastapi import FastAPI, Request, Depends, HTTPException, status
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
import httpx
import redis
from datetime import datetime, timedelta
from typing import Optional, List
import json

# Add shared module to path
sys.path.append(str(Path(__file__).parent.parent / "shared"))

from schemas import User, UserCreate, UserLogin, Stage, StageProgress, StageStatus
from database import get_db, User as DBUser, Stage as DBStage, StageProgress as DBStageProgress
from sqlalchemy.orm import Session

# Configuration
CORE_API_URL = os.getenv("CORE_API_URL", "http://core-api:8080")
REDIS_URL = os.getenv("REDIS_URL", "redis://redis:6379")

app = FastAPI(title="Apollo 11 Astronaut Onboarding", version="1.0.0")

# Static files and templates
app.mount("/static", StaticFiles(directory="static"), name="static")
templates = Jinja2Templates(directory="templates")

# Security
security = HTTPBearer()

# Redis connection
redis_client = redis.from_url(REDIS_URL)

# HTTP client for core API
http_client = httpx.AsyncClient(base_url=CORE_API_URL)


def get_current_user(credentials: HTTPAuthorizationCredentials = Depends(security), db: Session = Depends(get_db)) -> DBUser:
    """Get current authenticated user"""
    # In a real app, you'd verify the JWT token here
    # For simplicity, we'll use a basic token approach
    token = credentials.credentials
    user_id = redis_client.get(f"token:{token}")
    
    if not user_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authentication credentials"
        )
    
    user = db.query(DBUser).filter(DBUser.id == int(user_id)).first()
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User not found"
        )
    
    return user


@app.get("/", response_class=HTMLResponse)
async def home(request: Request):
    """Home page"""
    return templates.TemplateResponse("index.html", {"request": request})


@app.get("/login", response_class=HTMLResponse)
async def login_page(request: Request):
    """Login page"""
    return templates.TemplateResponse("login.html", {"request": request})


@app.get("/register", response_class=HTMLResponse)
async def register_page(request: Request):
    """Registration page"""
    return templates.TemplateResponse("register.html", {"request": request})


@app.get("/dashboard", response_class=HTMLResponse)
async def dashboard(request: Request, user: DBUser = Depends(get_current_user), db: Session = Depends(get_db)):
    """User dashboard with stage progress"""
    # Get user's stage progress
    stage_progress = db.query(DBStageProgress).filter(DBStageProgress.user_id == user.id).all()
    
    # Get all stages
    stages = db.query(DBStage).order_by(DBStage.id).all()
    
    # Create stage data with progress
    stage_data = []
    for stage in stages:
        progress = next((p for p in stage_progress if p.stage_id == stage.id), None)
        stage_data.append({
            "id": stage.id,
            "name": stage.name,
            "description": stage.description,
            "status": progress.status if progress else "locked",
            "attempts": progress.attempts if progress else 0,
            "completed_at": progress.completed_at if progress else None
        })
    
    return templates.TemplateResponse("dashboard.html", {
        "request": request,
        "user": user,
        "stages": stage_data
    })


@app.get("/stage/{stage_id}", response_class=HTMLResponse)
async def stage_page(request: Request, stage_id: int, user: DBUser = Depends(get_current_user), db: Session = Depends(get_db)):
    """Individual stage page"""
    # Get stage details
    stage = db.query(DBStage).filter(DBStage.id == stage_id).first()
    if not stage:
        raise HTTPException(status_code=404, detail="Stage not found")
    
    # Get user's progress for this stage
    progress = db.query(DBStageProgress).filter(
        DBStageProgress.user_id == user.id,
        DBStageProgress.stage_id == stage_id
    ).first()
    
    if not progress or progress.status == "locked":
        raise HTTPException(status_code=403, detail="Stage is locked")
    
    return templates.TemplateResponse("stage.html", {
        "request": request,
        "user": user,
        "stage": stage,
        "progress": progress
    })


@app.post("/api/register")
async def register(user_data: UserCreate, db: Session = Depends(get_db)):
    """Register a new user"""
    # Check if user already exists
    existing_user = db.query(DBUser).filter(
        (DBUser.username == user_data.username) | (DBUser.email == user_data.email)
    ).first()
    
    if existing_user:
        raise HTTPException(status_code=400, detail="Username or email already exists")
    
    # Create new user (in real app, hash the password)
    new_user = DBUser(
        username=user_data.username,
        email=user_data.email,
        full_name=user_data.full_name,
        password_hash=user_data.password  # In real app, use proper hashing
    )
    
    db.add(new_user)
    db.commit()
    db.refresh(new_user)
    
    # Initialize stage progress for new user
    stages = db.query(DBStage).all()
    for stage in stages:
        status = "available" if stage.id == 1 else "locked"
        progress = DBStageProgress(
            user_id=new_user.id,
            stage_id=stage.id,
            status=status
        )
        db.add(progress)
    
    db.commit()
    
    return {"message": "User registered successfully", "user_id": new_user.id}


@app.post("/api/login")
async def login(login_data: UserLogin, db: Session = Depends(get_db)):
    """Login user"""
    user = db.query(DBUser).filter(DBUser.username == login_data.username).first()
    
    if not user or user.password_hash != login_data.password:  # In real app, verify hashed password
        raise HTTPException(status_code=401, detail="Invalid credentials")
    
    # Generate token (in real app, use JWT)
    token = f"token_{user.id}_{datetime.utcnow().timestamp()}"
    redis_client.setex(f"token:{token}", timedelta(hours=24), user.id)
    
    return {"access_token": token, "token_type": "bearer", "user": user}


@app.post("/api/stage/{stage_id}/start")
async def start_stage(stage_id: int, user: DBUser = Depends(get_current_user), db: Session = Depends(get_db)):
    """Start a stage simulation"""
    # Get stage progress
    progress = db.query(DBStageProgress).filter(
        DBStageProgress.user_id == user.id,
        DBStageProgress.stage_id == stage_id
    ).first()
    
    if not progress or progress.status not in ["available", "failed"]:
        raise HTTPException(status_code=403, detail="Stage not available")
    
    # Update progress to in_progress
    progress.status = "in_progress"
    progress.attempts += 1
    db.commit()
    
    # Send simulation request to core API
    simulation_data = {
        "user_id": user.id,
        "stage_id": stage_id,
        "attempt_number": progress.attempts,
        "simulation_data": {"stage_name": f"Stage {stage_id}"}
    }
    
    try:
        response = await http_client.post("/api/simulation/start", json=simulation_data)
        if response.status_code == 200:
            return {"message": "Simulation started", "simulation_id": response.json().get("simulation_id")}
        else:
            raise HTTPException(status_code=500, detail="Failed to start simulation")
    except httpx.RequestError:
        raise HTTPException(status_code=500, detail="Core API unavailable")


@app.get("/api/user/progress")
async def get_user_progress(user: DBUser = Depends(get_current_user), db: Session = Depends(get_db)):
    """Get user's progress across all stages"""
    stage_progress = db.query(DBStageProgress).filter(DBStageProgress.user_id == user.id).all()
    stages = db.query(DBStage).order_by(DBStage.id).all()
    
    progress_data = []
    for stage in stages:
        progress = next((p for p in stage_progress if p.stage_id == stage.id), None)
        progress_data.append({
            "stage_id": stage.id,
            "stage_name": stage.name,
            "status": progress.status if progress else "locked",
            "attempts": progress.attempts if progress else 0,
            "completed_at": progress.completed_at.isoformat() if progress and progress.completed_at else None
        })
    
    return {"user_id": user.id, "progress": progress_data}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
