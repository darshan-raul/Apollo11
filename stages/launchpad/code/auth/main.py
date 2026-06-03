# Apollo11 Auth Service - FastAPI
from fastapi import FastAPI, HTTPException, Depends
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, EmailStr
from typing import Optional
import uuid
from datetime import datetime, timedelta

app = FastAPI(title="Apollo11 Auth Service")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)
security = HTTPBearer()

# In-memory stub storage (replace with PostgreSQL in production)
users_db = {}
tokens_db = {}

class UserRegister(BaseModel):
    email: str
    password: str
    full_name: str

class UserLogin(BaseModel):
    email: str
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

# JWT stub - use python-jose in production
def create_token(user_id: str, email: str, role: str) -> str:
    return f"stub_token_{user_id}_{int(datetime.utcnow().timestamp())}"

@app.get("/health")
async def health():
    return {"status": "ok"}

@app.post("/register", response_model=UserResponse)
async def register(data: UserRegister):
    for u in users_db.values():
        if u["email"] == data.email:
            raise HTTPException(status_code=409, detail="Email already exists")
    
    user_id = str(uuid.uuid4())
    user = {
        "id": user_id,
        "email": data.email,
        "password": data.password,  # Hash in production
        "full_name": data.full_name,
        "role": "patron",
        "created_at": datetime.utcnow().isoformat()
    }
    users_db[user_id] = user
    return UserResponse(id=user_id, email=user["email"], full_name=user["full_name"], role=user["role"])

@app.post("/login", response_model=TokenResponse)
async def login(data: UserLogin):
    for u in users_db.values():
        if u["email"] == data.email and u["password"] == data.password:
            token = create_token(u["id"], u["email"], u["role"])
            tokens_db[token] = u["id"]
            return TokenResponse(access_token=token, token_type="Bearer", expires_in=3600)
    raise HTTPException(status_code=401, detail="Invalid credentials")

@app.get("/me", response_model=UserResponse)
async def me(credentials: HTTPAuthorizationCredentials = Depends(security)):
    token = credentials.credentials
    user_id = tokens_db.get(token)
    if not user_id:
        raise HTTPException(status_code=401, detail="Invalid token")
    user = users_db.get(user_id)
    if not user:
        raise HTTPException(status_code=401, detail="User not found")
    return UserResponse(id=user["id"], email=user["email"], full_name=user["full_name"], role=user["role"])

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)