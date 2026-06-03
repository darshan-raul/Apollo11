"""
Apollo11 Auth Service - FastAPI + PostgreSQL + JWT
Stage4: adds /healthz/startup, /healthz/live, /healthz/ready probe handlers
"""
import os
import uuid
from datetime import datetime, timedelta, timezone
from contextlib import contextmanager
from typing import Optional
import time

import psycopg2
from psycopg2 import pool
from psycopg2.extras import RealDictCursor

from fastapi import FastAPI, HTTPException, Depends, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from pydantic import BaseModel, EmailStr, field_validator
from passlib.context import CryptContext
from jose import JWTError, jwt

# Startup time for startup probe
STARTUP_TIME = time.time()

# =============================================================================
# Configuration
# =============================================================================

DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://postgres:***@auth-postgres:5432/auth")
JWT_SECRET = os.getenv("JWT_SECRET", "dev-secret-change-in-prod")
JWT_ALGORITHM = "HS256"
JWT_EXPIRATION_HOURS = 1

# =============================================================================
# Password hashing
# =============================================================================

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

# =============================================================================
# Database connection pool
# =============================================================================

_connection_pool: Optional[pool.ThreadedConnectionPool] = None


def _get_pool() -> pool.ThreadedConnectionPool:
    global _connection_pool
    if _connection_pool is None:
        _connection_pool = pool.ThreadedConnectionPool(
            minconn=2,
            maxconn=10,
            dsn=DATABASE_URL,
        )
    return _connection_pool


@contextmanager
def get_db_connection():
    """Context manager for database connections."""
    pg_pool = _get_pool()
    conn = pg_pool.getconn()
    try:
        yield conn
    finally:
        pg_pool.putconn(conn)


@contextmanager
def get_db_cursor(cursor_factory=RealDictCursor):
    """Context manager for database cursors."""
    with get_db_connection() as conn:
        cursor = conn.cursor(cursor_factory=cursor_factory)
        try:
            yield cursor
            conn.commit()
        except Exception:
            conn.rollback()
            raise
        finally:
            cursor.close()


def init_db():
    """Initialize database tables if they don't exist."""
    with get_db_connection() as conn:
        cursor = conn.cursor()
        cursor.execute("""
            CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
        """)
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS users (
                id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
                email VARCHAR(255) UNIQUE NOT NULL,
                password_hash VARCHAR(255) NOT NULL,
                full_name VARCHAR(255) NOT NULL,
                role VARCHAR(50) NOT NULL DEFAULT 'patron',
                created_at TIMESTAMP NOT NULL DEFAULT NOW(),
                updated_at TIMESTAMP NOT NULL DEFAULT NOW()
            );
        """)
        cursor.execute("""
            CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
        """)
        conn.commit()
        cursor.close()


# =============================================================================
# FastAPI app
# =============================================================================

app = FastAPI(
    title="Apollo11 Auth Service",
    description="Authentication service for Apollo11 library management",
    version="1.0.0",
)

security = HTTPBearer()


@app.on_event("startup")
async def startup_event():
    """Initialize database on startup."""
    init_db()


@app.on_event("shutdown")
async def shutdown_event():
    """Close database pool on shutdown."""
    global _connection_pool
    if _connection_pool:
        _connection_pool.closeall()
        _connection_pool = None


# =============================================================================
# Probe endpoints (Stage4)
# =============================================================================

@app.get("/healthz/startup", tags=["health"])
async def startup_probe():
    """Startup probe: healthy after initial boot (5s delay)."""
    elapsed = time.time() - STARTUP_TIME
    if elapsed < 5.0:
        from fastapi.responses import JSONResponse
        return JSONResponse(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            content={"status": "starting", "elapsed": round(elapsed, 2)},
        )
    return {"status": "ready"}


@app.get("/healthz/live", tags=["health"])
async def liveness_probe():
    """Liveness probe: service is alive."""
    return {"status": "alive"}


@app.get("/healthz/ready", tags=["health"])
async def readiness_probe():
    """Readiness probe: service can handle traffic (DB conn ok)."""
    try:
        with get_db_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT 1")
            cursor.close()
        return {"status": "ready"}
    except Exception as e:
        from fastapi.responses import JSONResponse
        return JSONResponse(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            content={"status": "not ready", "error": str(e)},
        )


# =============================================================================
# Pydantic models
# =============================================================================

class UserRegister(BaseModel):
    email: EmailStr
    password: str
    full_name: str

    @field_validator("password")
    @classmethod
    def password_min_length(cls, v: str) -> str:
        if len(v) < 6:
            raise ValueError("Password must be at least 6 characters")
        return v


class UserLogin(BaseModel):
    email: EmailStr
    password: str


class UserResponse(BaseModel):
    id: str
    email: str
    full_name: str
    role: str


class TokenResponse(BaseModel):
    access_token: str
    token_type: str
    expires_in: int


# =============================================================================
# JWT functions
# =============================================================================

def create_access_token(user_id: str, email: str, role: str) -> str:
    """Create a JWT access token."""
    expire = datetime.now(timezone.utc) + timedelta(hours=JWT_EXPIRATION_HOURS)
    payload = {
        "sub": user_id,
        "email": email,
        "role": role,
        "exp": expire,
        "iat": datetime.now(timezone.utc),
    }
    return jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGORITHM)


def decode_token(token: str) -> dict:
    """Decode and validate a JWT token."""
    try:
        payload = jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
        return payload
    except JWTError as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Invalid token: {str(e)}",
            headers={"WWW-Authenticate": "Bearer"},
        )


# =============================================================================
# Security dependencies
# =============================================================================

def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security),
) -> dict:
    """Dependency to get the current authenticated user from JWT token."""
    payload = decode_token(credentials.credentials)
    user_id = payload.get("sub")
    if not user_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token payload",
            headers={"WWW-Authenticate": "Bearer"},
        )

    with get_db_cursor() as cursor:
        cursor.execute(
            "SELECT id, email, full_name, role FROM users WHERE id = %s",
            (user_id,)
        )
        user = cursor.fetchone()

    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User not found",
            headers={"WWW-Authenticate": "Bearer"},
        )

    user_dict = dict(user)
    return user_dict


# =============================================================================
# Endpoints
# =============================================================================

@app.get("/health", tags=["health"])
async def health_check():
    """Legacy health check endpoint."""
    return {"status": "ok"}


@app.post("/register", response_model=UserResponse, status_code=status.HTTP_201_CREATED, tags=["auth"])
async def register(data: UserRegister):
    """Register a new user."""
    password_hash = pwd_context.hash(data.password)

    try:
        with get_db_cursor() as cursor:
            cursor.execute(
                """
                INSERT INTO users (email, password_hash, full_name, role)
                VALUES (%s, %s, %s, 'patron')
                RETURNING id, email, full_name, role
                """,
                (data.email, password_hash, data.full_name),
            )
            result = cursor.fetchone()
            return UserResponse(
                id=str(result["id"]),
                email=result["email"],
                full_name=result["full_name"],
                role=result["role"],
            )
    except psycopg2.errors.UniqueViolation:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Email already registered",
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Registration failed: {str(e)}",
        )


@app.post("/login", response_model=TokenResponse, tags=["auth"])
async def login(data: UserLogin):
    """Authenticate user and return JWT token."""
    with get_db_cursor() as cursor:
        cursor.execute(
            "SELECT id, email, password_hash, full_name, role FROM users WHERE email = %s",
            (data.email,),
        )
        user = cursor.fetchone()

    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email or password",
        )

    user_dict = dict(user)

    if not pwd_context.verify(data.password, user_dict["password_hash"]):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email or password",
        )

    access_token = create_access_token(
        user_id=str(user_dict["id"]),
        email=user_dict["email"],
        role=user_dict["role"],
    )

    return TokenResponse(
        access_token=access_token,
        token_type="Bearer",
        expires_in=JWT_EXPIRATION_HOURS * 3600,
    )


@app.get("/me", response_model=UserResponse, tags=["auth"])
async def get_me(current_user: dict = Depends(get_current_user)):
    """Get current authenticated user info."""
    return UserResponse(
        id=str(current_user["id"]),
        email=current_user["email"],
        full_name=current_user["full_name"],
        role=current_user["role"],
    )


# =============================================================================
# Main
# =============================================================================

if __name__ == "__main__":
    import uvicorn

    port = int(os.getenv("PORT", "8080"))
    uvicorn.run(app, host="0.0.0.0", port=port)