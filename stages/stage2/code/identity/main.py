import os
import re
import json
import uuid
import datetime
from contextlib import asynccontextmanager
from decimal import Decimal
from typing import Optional

import psycopg2
import psycopg2.errors
import bcrypt
from psycopg2.extras import RealDictCursor
from fastapi import FastAPI, HTTPException, Header, Depends, Request
from fastapi.responses import JSONResponse, PlainTextResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from jose import jwt, JWTError

JWT_SECRET = os.getenv("JWT_SECRET", "apollo-airlines-dev-secret")
JWT_ALGORITHM = "HS256"
JWT_EXPIRY_HOURS = 24

DB_URL = os.getenv("DATABASE_URL", "postgresql://postgres:postgres@identity-db:5432/identity")


def get_db():
    conn = psycopg2.connect(DB_URL)
    return conn


def generate_request_id():
    return str(uuid.uuid4())


EMAIL_PATTERN = re.compile(r"^[^\s@]+@[^\s@]+\.[^\s@]+$")
MIN_PASSWORD_LENGTH = 6


def is_uuid(value: str) -> bool:
    try:
        uuid.UUID(value)
        return True
    except (ValueError, AttributeError, TypeError):
        return False


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

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


class RegisterRequest(BaseModel):
    email: str
    password: str


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


@app.get("/healthz")
async def healthz():
    return JSONResponse({"status": "ok"})


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
    return PlainTextResponse(
        "# HELP http_requests_total Total HTTP requests observed by the service.\n"
        "# TYPE http_requests_total counter\n"
        'http_requests_total{service="identity"} 0\n'
        "# HELP http_request_duration_ms Most recently observed request duration in milliseconds.\n"
        "# TYPE http_request_duration_ms gauge\n"
        'http_request_duration_ms{service="identity"} 0\n'
        "# HELP db_connections_active Active database connections owned by the service.\n"
        "# TYPE db_connections_active gauge\n"
        f'db_connections_active{{service="identity"}} {active}\n',
        media_type="text/plain; version=0.0.4",
    )


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
    if not EMAIL_PATTERN.match(body.email):
        raise HTTPException(status_code=400, detail="A valid email address is required")
    if len(body.password) < MIN_PASSWORD_LENGTH:
        raise HTTPException(status_code=400, detail=f"Password must be at least {MIN_PASSWORD_LENGTH} characters")
    try:
        conn = get_db()
        cur = conn.cursor(cursor_factory=RealDictCursor)
        cur.execute("SELECT id FROM users WHERE email = %s", (body.email,))
        existing = cur.fetchone()
        if existing:
            cur.close()
            conn.close()
            raise HTTPException(status_code=409, detail="Email already registered")
        password_hash = bcrypt.hashpw(body.password.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")
        cur.execute(
            """INSERT INTO users (email, password_hash)
               VALUES (%s, %s)
               RETURNING id, email, loyalty_tier, role""",
            (body.email, password_hash)
        )
        user = cur.fetchone()
        conn.commit()
        cur.close()
        conn.close()
        log_json("INFO", "identity-service", "User registered", trace_id=trace_id, email=body.email)
        return {
            "id": str(user["id"]),
            "email": user["email"],
            "loyaltyTier": user["loyalty_tier"],
            "role": user["role"]
        }
    except HTTPException:
        raise
    except psycopg2.errors.UniqueViolation:
        # Two registrations for the same email raced past the lookup above.
        raise HTTPException(status_code=409, detail="Email already registered")
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
    if not bcrypt.checkpw(body.password.encode("utf-8"), user["password_hash"].encode("utf-8")):
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
    if not is_uuid(user_id):
        raise HTTPException(status_code=400, detail="Invalid user ID")
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


@app.get("/api/admin/users")
async def get_all_users(authorization: str = Header(None), request: Request = None):
    trace_id = getattr(request.state, "request_id", "")
    payload = verify_jwt(authorization)
    if payload.get("role") != "ADMIN":
        raise HTTPException(status_code=403, detail="Admin access required")
    conn = get_db()
    cur = conn.cursor(cursor_factory=RealDictCursor)
    cur.execute(
        """SELECT id, email, first_name, last_name, loyalty_tier, role, is_active, created_at
           FROM users ORDER BY created_at DESC"""
    )
    rows = cur.fetchall()
    cur.close()
    conn.close()
    log_json("INFO", "identity-service", "Admin fetched all users", trace_id=trace_id, count=len(rows))
    return {
        "users": [
            {
                "id": str(u["id"]),
                "email": u["email"],
                "firstName": u["first_name"],
                "lastName": u["last_name"],
                "loyaltyTier": u["loyalty_tier"],
                "role": u["role"],
                "isActive": u["is_active"],
                "createdAt": u["created_at"].isoformat() + "Z" if u["created_at"] else None,
            }
            for u in rows
        ]
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)
