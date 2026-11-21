import os
import re
import json
import uuid
import datetime
import logging
from contextlib import asynccontextmanager
from decimal import Decimal
from typing import Optional

import bcrypt
import psycopg2
import psycopg2.errors
from psycopg2.extras import RealDictCursor
from fastapi import FastAPI, HTTPException, Header, Depends, Request
from fastapi.responses import JSONResponse, Response
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
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
from prometheus_client import generate_latest, CONTENT_TYPE_LATEST, REGISTRY, Counter, Histogram

JWT_SECRET = os.getenv("JWT_SECRET", "apollo-airlines-dev-secret")
JWT_ALGORITHM = "HS256"
JWT_EXPIRY_HOURS = 24


DB_URL = os.getenv("DATABASE_URL", "postgresql://postgres:postgres@identity-db:5432/identity")
OTEL_ENDPOINT = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "otel-collector:4317")

HTTP_REQUESTS_TOTAL = Counter(
    "http_requests_total",
    "Total HTTP requests by service, method, path, status.",
    ["service", "method", "path", "status"],
)
HTTP_REQUEST_DURATION_MS = Histogram(
    "http_request_duration_ms",
    "HTTP request latency in milliseconds.",
    ["service", "method", "path"],
    buckets=(1, 5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000),
)


def get_db():
    conn = psycopg2.connect(DB_URL, connect_timeout=5)
    return conn


def close_quietly(cur=None, conn=None):
    if cur is not None:
        try:
            cur.close()
        except Exception:
            pass
    if conn is not None:
        try:
            conn.close()
        except Exception:
            pass


def get_request_id(request: Optional[Request]) -> str:
    return getattr(getattr(request, "state", None), "request_id", "")


def generate_request_id():
    return str(uuid.uuid4())


def current_trace_ids():
    """Read trace_id + span_id from the active OTEL span (if any)."""
    span = trace.get_current_span()
    sc = span.get_span_context()
    if not sc.is_valid:
        return "", ""
    return f"{sc.trace_id:032x}", f"{sc.span_id:016x}"


EMAIL_PATTERN = re.compile(r"^[^\s@]+@[^\s@]+\.[^\s@]+$")
MIN_PASSWORD_LENGTH = 6


def is_uuid(value: str) -> bool:
    try:
        uuid.UUID(value)
        return True
    except (ValueError, AttributeError, TypeError):
        return False


def log_json(level: str, service: str, message: str, trace_id: str = "", span_id: str = "", request_id: str = "", **kwargs):
    if not trace_id or not span_id:
        cur_trace, cur_span = current_trace_ids()
        trace_id = trace_id or cur_trace
        span_id = span_id or cur_span
    entry = {
        "timestamp": datetime.datetime.utcnow().isoformat() + "Z",
        "level": level,
        "service": service,
        "request_id": request_id,
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
    if hasattr(provider, "shutdown"):
        provider.shutdown()
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
    firstName: Optional[str] = None
    lastName: Optional[str] = None
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
    started = datetime.datetime.now(datetime.timezone.utc)
    request_id = request.headers.get("X-Request-ID") or generate_request_id()
    request.state.request_id = request_id
    status_code = 500
    response = None
    try:
        response = await call_next(request)
        status_code = response.status_code
        response.headers["X-Request-ID"] = request_id
        return response
    finally:
        if request.url.path != "/metrics":
            route = request.scope.get("route")
            path = getattr(route, "path", request.url.path)
            elapsed_ms = (datetime.datetime.now(datetime.timezone.utc) - started).total_seconds() * 1000
            HTTP_REQUESTS_TOTAL.labels("identity", request.method, path, str(status_code)).inc()
            HTTP_REQUEST_DURATION_MS.labels("identity", request.method, path).observe(elapsed_ms)


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
    conn = None
    cur = None
    try:
        conn = get_db()
        cur = conn.cursor()
        cur.execute("SELECT 1")
        return JSONResponse({"status": "ready"})
    except Exception as e:
        return JSONResponse({"status": "error", "detail": str(e)}, status_code=503)
    finally:
        close_quietly(cur, conn)


@app.get("/readyz")
async def readyz():
    conn = None
    cur = None
    try:
        conn = get_db()
        cur = conn.cursor()
        cur.execute("SELECT 1")
        return JSONResponse({"status": "ok"})
    except Exception as e:
        return JSONResponse({"status": "error", "detail": str(e)}, status_code=503)
    finally:
        close_quietly(cur, conn)


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


@app.post("/api/users/register", status_code=201)
async def register(body: RegisterRequest, request: Request):
    request_id = get_request_id(request)
    trace_id, span_id = current_trace_ids()
    if not EMAIL_PATTERN.match(body.email):
        raise HTTPException(status_code=400, detail="A valid email address is required")
    if len(body.password) < MIN_PASSWORD_LENGTH:
        raise HTTPException(status_code=400, detail=f"Password must be at least {MIN_PASSWORD_LENGTH} characters")
    conn = None
    cur = None
    try:
        conn = get_db()
        cur = conn.cursor(cursor_factory=RealDictCursor)
        cur.execute("SELECT id FROM users WHERE email = %s", (body.email,))
        existing = cur.fetchone()
        if existing:
            raise HTTPException(status_code=409, detail="Email already registered")
        password_hash = bcrypt.hashpw(body.password.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")
        cur.execute(
            """INSERT INTO users (email, password_hash, first_name, last_name, passport_number)
               VALUES (%s, %s, %s, %s, %s)
               RETURNING id, email, first_name, last_name, passport_number, loyalty_tier, role""",
            (body.email, password_hash, body.firstName, body.lastName, body.passportNumber)
        )
        user = cur.fetchone()
        conn.commit()
        log_json("INFO", "identity-service", "User registered", trace_id=trace_id, span_id=span_id, request_id=request_id, email=body.email)
        return {
            "id": str(user["id"]),
            "email": user["email"],
            "firstName": user["first_name"],
            "lastName": user["last_name"],
            "passportNumber": user["passport_number"],
            "loyaltyTier": user["loyalty_tier"],
            "role": user["role"]
        }
    except HTTPException:
        if conn:
            conn.rollback()
        raise
    except psycopg2.errors.UniqueViolation:
        if conn:
            conn.rollback()
        # Two registrations for the same email raced past the lookup above.
        raise HTTPException(status_code=409, detail="Email already registered")
    except Exception as e:
        if conn:
            conn.rollback()
        log_json("ERROR", "identity-service", str(e), trace_id=trace_id, span_id=span_id, request_id=request_id)
        raise HTTPException(status_code=500, detail="Registration failed")
    finally:
        close_quietly(cur, conn)


@app.post("/api/users/login")
async def login(body: LoginRequest, request: Request):
    request_id = get_request_id(request)
    trace_id, span_id = current_trace_ids()
    conn = None
    cur = None
    try:
        conn = get_db()
        cur = conn.cursor(cursor_factory=RealDictCursor)
        cur.execute("SELECT * FROM users WHERE email = %s", (body.email,))
        user = cur.fetchone()
    finally:
        close_quietly(cur, conn)
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
    log_json("INFO", "identity-service", "User logged in", trace_id=trace_id, span_id=span_id, request_id=request_id, email=body.email)
    return {
        "token": token,
        "expiresAt": expires_at.isoformat() + "Z"
    }


@app.get("/api/users/me")
async def get_me(authorization: str = Header(None), request: Request = None):
    payload = verify_jwt(authorization)
    user_id = payload.get("sub")
    if not user_id or not is_uuid(user_id):
        raise HTTPException(status_code=401, detail="Invalid token claims")
    conn = None
    cur = None
    try:
        conn = get_db()
        cur = conn.cursor(cursor_factory=RealDictCursor)
        cur.execute("SELECT * FROM users WHERE id = %s", (user_id,))
        user = cur.fetchone()
    finally:
        close_quietly(cur, conn)
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
    request_id = get_request_id(request)
    trace_id, span_id = current_trace_ids()
    payload = verify_jwt(authorization)
    user_id = payload.get("sub")
    if not user_id or not is_uuid(user_id):
        raise HTTPException(status_code=401, detail="Invalid token claims")
    updates = []
    values = []
    if body.firstName is not None:
        updates.append("first_name = %s")
        values.append(body.firstName)
    if body.lastName is not None:
        updates.append("last_name = %s")
        values.append(body.lastName)
    if body.passportNumber is not None:
        updates.append("passport_number = %s")
        values.append(body.passportNumber)
    if not updates:
        raise HTTPException(status_code=400, detail="No fields to update")
    updates.append("updated_at = NOW()")
    values.append(user_id)
    conn = None
    cur = None
    try:
        conn = get_db()
        cur = conn.cursor(cursor_factory=RealDictCursor)
        cur.execute(
            f"UPDATE users SET {', '.join(updates)} WHERE id = %s RETURNING *",
            tuple(values)
        )
        user = cur.fetchone()
        if not user:
            conn.rollback()
            raise HTTPException(status_code=404, detail="User not found")
        conn.commit()
    except HTTPException:
        raise
    except Exception as e:
        if conn:
            conn.rollback()
        log_json("ERROR", "identity-service", str(e), trace_id=trace_id, span_id=span_id, request_id=request_id)
        raise HTTPException(status_code=500, detail="Profile update failed")
    finally:
        close_quietly(cur, conn)
    log_json("INFO", "identity-service", "Profile updated", trace_id=trace_id, span_id=span_id, request_id=request_id, user_id=user_id)
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
    payload = verify_jwt(authorization)
    role = payload.get("role")
    token_user_id = payload.get("sub")
    if role != "ADMIN" and token_user_id != user_id:
        raise HTTPException(status_code=403, detail="Not authorized")
    if not is_uuid(user_id):
        raise HTTPException(status_code=400, detail="Invalid user ID")
    conn = None
    cur = None
    try:
        conn = get_db()
        cur = conn.cursor(cursor_factory=RealDictCursor)
        cur.execute("SELECT * FROM users WHERE id = %s", (user_id,))
        user = cur.fetchone()
    finally:
        close_quietly(cur, conn)
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
    request_id = get_request_id(request)
    trace_id, span_id = current_trace_ids()
    payload = verify_jwt(authorization)
    if payload.get("role") != "ADMIN":
        raise HTTPException(status_code=403, detail="Admin access required")
    conn = None
    cur = None
    try:
        conn = get_db()
        cur = conn.cursor(cursor_factory=RealDictCursor)
        cur.execute(
            """SELECT id, email, first_name, last_name, loyalty_tier, role, is_active, created_at
               FROM users ORDER BY created_at DESC"""
        )
        rows = cur.fetchall()
    finally:
        close_quietly(cur, conn)
    log_json("INFO", "identity-service", "Admin fetched all users", trace_id=trace_id, span_id=span_id, request_id=request_id, count=len(rows))
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


# --- Graceful shutdown (Stage 4) ---
# The image starts this file with `python main.py`, so the settings below
# apply. uvicorn's own signal handler calls Server.handle_exit, which starts
# the graceful drain. Subclassing keeps that behavior and adds one log line;
# replacing the handler with signal.signal() would log but never exit.
# timeout_graceful_shutdown gives in-flight requests up to 30 s, matching
# terminationGracePeriodSeconds.
if __name__ == "__main__":
    import uvicorn

    class LoggingServer(uvicorn.Server):
        def handle_exit(self, sig, frame):
            log_json("INFO", "identity-service", "Received SIGTERM, shutting down gracefully", trace_id="")
            super().handle_exit(sig, frame)

    port = int(os.getenv("PORT", "8080"))
    LoggingServer(uvicorn.Config(
        app,
        host="0.0.0.0",
        port=port,
        timeout_graceful_shutdown=30,
        access_log=False,
    )).run()
