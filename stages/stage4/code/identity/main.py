import os
import json
import uuid
import datetime
import signal
import sys
from contextlib import asynccontextmanager
from decimal import Decimal
from typing import Optional

import psycopg2
from psycopg2.extras import RealDictCursor
from fastapi import FastAPI, HTTPException, Header, Depends, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from passlib.context import CryptContext
from jose import jwt, JWTError

JWT_SECRET = os.getenv("JWT_SECRET", "apollo-airlines-dev-secret")
JWT_ALGORITHM = "HS256"
JWT_EXPIRY_HOURS = 24

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

DB_URL = os.getenv("DATABASE_URL", "postgresql://postgres:***@identity-db:5432/identity")

# Graceful shutdown flag
shutdown_requested = False


def get_db():
    conn = psycopg2.connect(DB_URL)
    return conn


def generate_request_id():
    return str(uuid.uuid4())


def log_json(level: str, service: str, message: str, trace_id: str = "", span_id: str = "", **kwargs):
    entry = {
        "timestamp": datetime.datetime.utcnow().isoformat() + "Z",
        "level": level,
        "service": service,
        "trace_id": trace_id,
        "span_id": span_id,
        "message": message,
    }
    entry.update(kwargs)
    print(json.dumps(entry))


@asynccontextmanager
async def lifespan(app: FastAPI):
    conn = get_db()
    yield
    conn.close()


app = FastAPI(title="identity-service", version="1.0.0", lifespan=lifespan)


class RegisterRequest(BaseModel):
    email: str
    password: str
    firstName: str
    lastName: str
    passportNumber: Optional[str] = None


class LoginRequest(BaseModel):
    email: str
    password: str


class UpdateProfileRequest(BaseModel):
    firstName: Optional[str] = None
    lastName: Optional[str] = None
    passportNumber: Optional[str] = None


@app.middleware("http")
async def add_request_id(request: Request, call_next):
    request_id = request.headers.get("X-Request-ID", generate_request_id())
    request.state.request_id = request_id
    response = await call_next(request)
    response.headers["X-Request-ID"] = request_id
    return response


# --- Stage 4: Probe handlers ---
@app.get("/healthz")
async def healthz():
    return JSONResponse({"status": "ok"})


@app.get("/healthz/startup")
async def healthz_startup():
    return JSONResponse({"status": "ok"})


@app.get("/healthz/live")
async def healthz_live():
    return JSONResponse({"status": "ok"})


@app.get("/healthz/ready")
async def healthz_ready():
    try:
        conn = get_db()
        cur = conn.cursor()
        cur.execute("SELECT 1")
        cur.close()
        conn.close()
        return JSONResponse({"status": "ok"})
    except Exception as e:
        return JSONResponse({"status": "error", "detail": str(e)}, status_code=503)


@app.get("/readyz")
async def readyz():
    try:
        conn = get_db()
        cur = conn.cursor()
        cur.execute("SELECT 1")
        cur.close()
        conn.close()
        return JSONResponse({"status": "ok"})
    except Exception as e:
        return JSONResponse({"status": "error", "detail": str(e)}, status_code=503)


@app.get("/metrics")
async def metrics():
    try:
        conn = get_db()
        cur = conn.cursor()
        cur.execute("SELECT 1")
        cur.close()
        conn.close()
        active = 1
    except:
        active = 0
    return JSONResponse({
        "service": "identity",
        "http_requests_total": 0,
        "http_request_duration_ms": 0,
        "db_connections_active": active
    })


def verify_jwt(authorization: str) -> dict:
    if not authorization:
        raise HTTPException(status_code=401, detail="Missing authorization header")
    parts = authorization.split(" ")
    if len(parts) != 2 or parts[0].lower() != "bearer":
        raise HTTPException(status_code=401, detail="Invalid authorization format")
    token = parts[1]
    try:
        payload = jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
        return payload
    except JWTError:
        raise HTTPException(status_code=401, detail="Invalid or expired token")


@app.post("/api/users/register")
async def register(body: RegisterRequest, request: Request):
    trace_id = getattr(request.state, "request_id", "")
    try:
        conn = get_db()
        cur = conn.cursor(cursor_factory=RealDictCursor)
        cur.execute("SELECT id FROM users WHERE email = %s", (body.email,))
        existing = cur.fetchone()
        if existing:
            cur.close()
            conn.close()
            raise HTTPException(status_code=409, detail="Email already registered")
        password_hash = pwd_context.hash(body.password)
        cur.execute(
            """INSERT INTO users (email, password_hash, first_name, last_name, passport_number)
               VALUES (%s, %s, %s, %s, %s)
               RETURNING id, email, first_name, last_name, loyalty_tier, role""",
            (body.email, password_hash, body.firstName, body.lastName, body.passportNumber)
        )
        user = cur.fetchone()
        conn.commit()
        cur.close()
        conn.close()
        log_json("INFO", "identity-service", "User registered", trace_id=trace_id, email=body.email)
        return {
            "id": str(user["id"]),
            "email": user["email"],
            "firstName": user["first_name"],
            "lastName": user["last_name"],
            "loyaltyTier": user["loyalty_tier"],
            "role": user["role"]
        }
    except HTTPException:
        raise
    except Exception as e:
        log_json("ERROR", "identity-service", str(e), trace_id=trace_id)
        raise HTTPException(status_code=500, detail="Registration failed")


@app.post("/api/users/login")
async def login(body: LoginRequest, request: Request):
    trace_id = getattr(request.state, "request_id", "")
    conn = get_db()
    cur = conn.cursor(cursor_factory=RealDictCursor)
    cur.execute("SELECT * FROM users WHERE email = %s", (body.email,))
    user = cur.fetchone()
    cur.close()
    conn.close()
    if not user:
        raise HTTPException(status_code=401, detail="Invalid credentials")
    if not pwd_context.verify(body.password, user["password_hash"]):
        raise HTTPException(status_code=401, detail="Invalid credentials")
    if not user["is_active"]:
        raise HTTPException(status_code=403, detail="Account is inactive")
    expires_at = datetime.datetime.utcnow() + datetime.timedelta(hours=JWT_EXPIRY_HOURS)
    token = jwt.encode(
        {
            "sub": str(user["id"]),
            "email": user["email"],
            "role": user["role"],
            "tier": user["loyalty_tier"],
            "exp": expires_at,
            "iat": datetime.datetime.utcnow()
        },
        JWT_SECRET,
        algorithm=JWT_ALGORITHM
    )
    log_json("INFO", "identity-service", "User logged in", trace_id=trace_id, email=body.email)
    return {
        "token": token,
        "expiresAt": expires_at.isoformat() + "Z"
    }


@app.get("/api/users/me")
async def get_me(authorization: str = Header(None), request: Request = None):
    trace_id = getattr(request.state, "request_id", "")
    payload = verify_jwt(authorization)
    user_id = payload.get("sub")
    conn = get_db()
    cur = conn.cursor(cursor_factory=RealDictCursor)
    cur.execute("SELECT * FROM users WHERE id = %s", (user_id,))
    user = cur.fetchone()
    cur.close()
    conn.close()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return {
        "id": str(user["id"]),
        "email": user["email"],
        "firstName": user["first_name"],
        "lastName": user["last_name"],
        "passportNumber": user["passport_number"],
        "loyaltyTier": user["loyalty_tier"],
        "role": user["role"]
    }


@app.put("/api/users/me")
async def update_me(body: UpdateProfileRequest, authorization: str = Header(None), request: Request = None):
    trace_id = getattr(request.state, "request_id", "")
    payload = verify_jwt(authorization)
    user_id = payload.get("sub")
    updates = []
    values = []
    if body.firstName:
        updates.append("first_name = %s")
        values.append(body.firstName)
    if body.lastName:
        updates.append("last_name = %s")
        values.append(body.lastName)
    if body.passportNumber:
        updates.append("passport_number = %s")
        values.append(body.passportNumber)
    if not updates:
        raise HTTPException(status_code=400, detail="No fields to update")
    updates.append("updated_at = NOW()")
    values.append(user_id)
    conn = get_db()
    cur = conn.cursor(cursor_factory=RealDictCursor)
    cur.execute(
        f"UPDATE users SET {', '.join(updates)} WHERE id = %s RETURNING *",
        tuple(values)
    )
    user = cur.fetchone()
    conn.commit()
    cur.close()
    conn.close()
    log_json("INFO", "identity-service", "Profile updated", trace_id=trace_id, user_id=user_id)
    return {
        "id": str(user["id"]),
        "email": user["email"],
        "firstName": user["first_name"],
        "lastName": user["last_name"],
        "passportNumber": user["passport_number"],
        "loyaltyTier": user["loyalty_tier"],
        "role": user["role"]
    }


@app.get("/api/users/{user_id}")
async def get_user_by_id(user_id: str, authorization: str = Header(None), request: Request = None):
    trace_id = getattr(request.state, "request_id", "")
    payload = verify_jwt(authorization)
    role = payload.get("role")
    token_user_id = payload.get("sub")
    if role != "ADMIN" and token_user_id != user_id:
        raise HTTPException(status_code=403, detail="Not authorized")
    conn = get_db()
    cur = conn.cursor(cursor_factory=RealDictCursor)
    cur.execute("SELECT * FROM users WHERE id = %s", (user_id,))
    user = cur.fetchone()
    cur.close()
    conn.close()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    if not user["is_active"]:
        raise HTTPException(status_code=403, detail="Account is inactive")
    return {
        "id": str(user["id"]),
        "email": user["email"],
        "firstName": user["first_name"],
        "lastName": user["last_name"],
        "passportNumber": user["passport_number"],
        "loyaltyTier": user["loyalty_tier"],
        "role": user["role"]
    }


# --- Graceful shutdown (Stage 4) ---
def handle_sigterm(signum, frame):
    log_json("INFO", "identity-service", "Received SIGTERM, shutting down gracefully", trace_id="")
    sys.exit(0)


signal.signal(signal.SIGTERM, handle_sigterm)
signal.signal(signal.SIGINT, handle_sigterm)


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)