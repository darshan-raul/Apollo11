import os
import json
import signal
import uuid
import datetime
import logging
from contextlib import asynccontextmanager
from decimal import Decimal
from typing import Optional

import psycopg2
from psycopg2.extras import RealDictCursor
from fastapi import FastAPI, HTTPException, Header, Depends, Request
from fastapi.responses import JSONResponse, Response
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from passlib.context import CryptContext
from jose import jwt, JWTError

# OpenTelemetry SDK + instrumentations
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.resources import Resource
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.psycopg2 import Psycopg2Instrumentor
from opentelemetry.instrumentation.requests import RequestsInstrumentor
from prometheus_client import generate_latest, CONTENT_TYPE_LATEST, REGISTRY

JWT_SECRET = os.getenv("JWT_SECRET", "apollo-airlines-dev-secret")
JWT_ALGORITHM = "HS256"
JWT_EXPIRY_HOURS = 24

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

DB_URL = os.getenv("DATABASE_URL", "postgresql://postgres:postgres@identity-db:5432/identity")
OTEL_ENDPOINT = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "otel-collector:4317")


def get_db():
    conn = psycopg2.connect(DB_URL)
    return conn


def generate_request_id():
    return str(uuid.uuid4())


def current_trace_ids():
    """Read trace_id + span_id from the active OTEL span (if any)."""
    span = trace.get_current_span()
    sc = span.get_span_context()
    if not sc.is_valid:
        return "", ""
    return f"{sc.trace_id:032x}", f"{sc.span_id:016x}"


def log_json(level: str, service: str, message: str, trace_id: str = "", span_id: str = "", **kwargs):
    if not trace_id:
        trace_id, span_id = current_trace_ids()
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
    log_json("INFO", "identity-service", "Service starting", trace_id="")
    yield
    # Flush any pending OTEL spans on shutdown
    provider = trace.get_tracer_provider()
    if hasattr(provider, "force_flush"):
        try:
            provider.force_flush(timeout_millis=2000)
        except Exception:
            pass
    log_json("INFO", "identity-service", "Lifespan shutdown complete", trace_id="")


# Initialize OpenTelemetry before app creation so the instrumentors hook
# into the right objects at construction time.
otel_resource = Resource.create({"service.name": "identity"})
otel_provider = TracerProvider(resource=otel_resource)
otel_exporter = OTLPSpanExporter(endpoint=OTEL_ENDPOINT, insecure=True)
otel_provider.add_span_processor(BatchSpanProcessor(otel_exporter))
trace.set_tracer_provider(otel_provider)
# Instrument psycopg2 so every DB call becomes a child span
Psycopg2Instrumentor().instrument()
# Instrument requests so outbound HTTP calls propagate traceparent
RequestsInstrumentor().instrument()

app = FastAPI(title="identity-service", version="1.0.0", lifespan=lifespan)
FastAPIInstrumentor.instrument_app(app)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=["X-Request-ID"],
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


@app.get("/healthz/startup")
async def healthz_startup():
    return JSONResponse({"status": "starting"})


@app.get("/healthz/live")
async def healthz_live():
    return JSONResponse({"status": "alive"})


@app.get("/healthz/ready")
async def healthz_ready():
    try:
        conn = get_db()
        cur = conn.cursor()
        cur.execute("SELECT 1")
        cur.close()
        conn.close()
        return JSONResponse({"status": "ready"})
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


# Stage 6: real Prometheus metrics endpoint.
# `prometheus_client.generate_latest()` returns the exposition format
# (text/plain; version=0.0.4) for all metrics in the default registry,
# which includes those auto-created by FastAPIInstrumentor +
# Psycopg2Instrumentor + RequestsInstrumentor.
@app.get("/metrics")
async def metrics():
    return Response(generate_latest(REGISTRY), media_type=CONTENT_TYPE_LATEST)


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
    trace_id, span_id = current_trace_ids()
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
            """INSERT INTO users (email, password_hash)
               VALUES (%s, %s)
               RETURNING id, email, loyalty_tier, role""",
            (body.email, password_hash)
        )
        user = cur.fetchone()
        conn.commit()
        cur.close()
        conn.close()
        log_json("INFO", "identity-service", "User registered", trace_id=trace_id, span_id=span_id, email=body.email)
        return {
            "id": str(user["id"]),
            "email": user["email"],
            "loyaltyTier": user["loyalty_tier"],
            "role": user["role"]
        }
    except HTTPException:
        raise
    except Exception as e:
        log_json("ERROR", "identity-service", str(e), trace_id=trace_id, span_id=span_id)
        raise HTTPException(status_code=500, detail="Registration failed")


@app.post("/api/users/login")
async def login(body: LoginRequest, request: Request):
    trace_id, span_id = current_trace_ids()
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
    log_json("INFO", "identity-service", "User logged in", trace_id=trace_id, span_id=span_id, email=body.email)
    return {
        "token": token,
        "expiresAt": expires_at.isoformat() + "Z"
    }


@app.get("/api/users/me")
async def get_me(authorization: str = Header(None), request: Request = None):
    trace_id, span_id = current_trace_ids()
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
    trace_id, span_id = current_trace_ids()
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
    log_json("INFO", "identity-service", "Profile updated", trace_id=trace_id, span_id=span_id, user_id=user_id)
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
    trace_id, span_id = current_trace_ids()
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


@app.get("/api/admin/users")
async def get_all_users(authorization: str = Header(None), request: Request = None):
    trace_id, span_id = current_trace_ids()
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
    log_json("INFO", "identity-service", "Admin fetched all users", trace_id=trace_id, span_id=span_id, count=len(rows))
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


def _log_sigterm(signum, frame):
    log_json("INFO", "identity-service", "Received SIGTERM, shutting down gracefully", trace_id="")


signal.signal(signal.SIGTERM, _log_sigterm)
signal.signal(signal.SIGINT, _log_sigterm)


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        app,
        host="0.0.0.0",
        port=8080,
        timeout_graceful_shutdown=30,
        access_log=False,
    )
