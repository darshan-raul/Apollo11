import os
import httpx
from fastapi import FastAPI, Request, Form, Depends, HTTPException, status, Response, Cookie
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from fastapi.responses import HTMLResponse, RedirectResponse, JSONResponse
from pydantic import BaseModel
from typing import Optional

app = FastAPI(title="Apollo 11 Frontend")

# Config
CORE_API_URL = os.getenv("CORE_API_URL", "http://core-api:8080")

# Static & Templates
app.mount("/static", StaticFiles(directory="static"), name="static")
templates = Jinja2Templates(directory="templates")

# Helper for Core API Calls
async def call_core_api(method: str, path: str, json_data: dict = None, params: dict = None) -> httpx.Response:
    async with httpx.AsyncClient() as client:
        url = f"{CORE_API_URL}{path}"
        if method == "GET":
            return await client.get(url, params=params)
        elif method == "POST":
            return await client.post(url, json=json_data)
    return None

# Dependency to get current user
async def get_user(user_id: str = Cookie(default=None)):
    if not user_id:
        return None
    # Verify user exists (optional, simply returning cookie value for now)
    return {"ID": user_id, "Username": "Cadet " + user_id} # Placeholder wrapper

# Routes
@app.get("/", response_class=HTMLResponse)
async def home(request: Request, user: dict = Depends(get_user)):
    if user:
        return RedirectResponse("/dashboard")
    return RedirectResponse("/login")

@app.get("/login", response_class=HTMLResponse)
async def login_page(request: Request):
    return templates.TemplateResponse("login.html", {"request": request})

@app.post("/login")
async def login(response: Response, username: str = Form(...), password: str = Form(...)):
    res = await call_core_api("POST", "/api/login", {"username": username, "password": password})
    if res.status_code == 200:
        data = res.json()
        response = RedirectResponse("/dashboard", status_code=302)
        response.set_cookie(key="user_id", value=str(data["id"]))
        return response
    else:
        return RedirectResponse("/login?error=InvalidCredentials", status_code=302)

@app.get("/logout")
async def logout(response: Response):
    response = RedirectResponse("/login", status_code=302)
    response.delete_cookie("user_id")
    return response

@app.get("/register", response_class=HTMLResponse)
async def register_page(request: Request):
    return templates.TemplateResponse("register.html", {"request": request})

@app.post("/register")
async def register(username: str = Form(...), password: str = Form(...)):
    res = await call_core_api("POST", "/api/register", {"username": username, "password": password})
    if res.status_code == 200:
        return RedirectResponse("/login?msg=Registered", status_code=302)
    return RedirectResponse("/register?error=Failed", status_code=302)

@app.get("/dashboard", response_class=HTMLResponse)
async def dashboard(request: Request, user_id: str = Cookie(default=None)):
    if not user_id:
        return RedirectResponse("/login")
    
    # Get Stages
    stages_res = await call_core_api("GET", "/api/stages")
    stages = stages_res.json() if stages_res.status_code == 200 else []

    # Get Progress
    progress_res = await call_core_api("GET", f"/api/user/{user_id}/progress")
    progress_list = progress_res.json() if progress_res.status_code == 200 else []
    
    # Merge Status
    for stage in stages:
        stage["status"] = "locked" # Default
        for p in progress_list:
            if p["stage_id"] == stage["id"]:
                stage["status"] = p["status"]
                break

    return templates.TemplateResponse("dashboard.html", {
        "request": request,
        "user": {"Username": "Cadet", "ID": user_id},
        "stages": stages
    })

@app.get("/stage/{stage_id}", response_class=HTMLResponse)
async def stage_page(request: Request, stage_id: int, user_id: str = Cookie(default=None)):
    if not user_id:
        return RedirectResponse("/login")

    stages_res = await call_core_api("GET", "/api/stages")
    stages = stages_res.json()
    stage = next((s for s in stages if s["id"] == stage_id), None)

    progress_res = await call_core_api("GET", f"/api/user/{user_id}/progress")
    progress_list = progress_res.json()
    progress = next((p for p in progress_list if p["stage_id"] == stage_id), None)

    return templates.TemplateResponse("stage.html", {
        "request": request, 
        "stage": stage, 
        "progress": progress,
        "user": {"ID": user_id}
    })

# API Proxy for client-side JS
class SimStart(BaseModel):
    stage_id: int

@app.post("/api/simulation/start")
async def start_sim_proxy(data: SimStart, user_id: str = Cookie(default=None)):
    if not user_id:
        raise HTTPException(status_code=401)
    
    payload = {"user_id": int(user_id), "stage_id": data.stage_id}
    res = await call_core_api("POST", "/api/simulation/start", payload)
    if res.status_code != 200:
        raise HTTPException(status_code=res.status_code, detail=res.text)
    return res.json()

@app.get("/api/status/{stage_id}")
async def get_stage_status(stage_id: int, user_id: str = Cookie(default=None)):
    if not user_id:
        raise HTTPException(status_code=401)
        
    progress_res = await call_core_api("GET", f"/api/user/{user_id}/progress")
    progress_list = progress_res.json()
    progress = next((p for p in progress_list if p["stage_id"] == stage_id), None)
    
    return {"status": progress["status"] if progress else "locked"}
