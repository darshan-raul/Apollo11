from sqlalchemy import Column, String, Integer, ForeignKey, DateTime, Enum, Boolean, func
from sqlalchemy.dialects.postgresql import UUID, JSONB
from sqlalchemy.orm import relationship
import uuid
import enum
from pydantic import BaseModel
from typing import Optional, List, Any
from datetime import datetime
from .database import Base

class StageStatus(str, enum.Enum):
    locked = "locked"
    in_progress = "in_progress"
    completed = "completed"

class User(Base):
    __tablename__ = "users"
    __table_args__ = {"schema": "core"}

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    keycloak_id = Column(String, unique=True, nullable=False)
    email = Column(String, nullable=False)
    created_at = Column(DateTime, default=func.now())

class Stage(Base):
    __tablename__ = "stages"
    __table_args__ = {"schema": "core"}

    id = Column(Integer, primary_key=True)
    name = Column(String, nullable=False)
    description = Column(String)
    order = Column(Integer, nullable=False)

class UserStageProgress(Base):
    __tablename__ = "user_stage_progress"
    __table_args__ = {"schema": "core"}

    user_id = Column(UUID(as_uuid=True), ForeignKey("core.users.id"), primary_key=True)
    stage_id = Column(Integer, ForeignKey("core.stages.id"), primary_key=True)
    status = Column(Enum(StageStatus, schema="core"), default=StageStatus.locked)
    updated_at = Column(DateTime, default=func.now(), onupdate=func.now())

# Pydantic Models for API
class UserBase(BaseModel):
    keycloak_id: str
    email: str

class UserCreate(UserBase):
    pass

class UserResponse(UserBase):
    id: uuid.UUID
    created_at: datetime
    class Config:
        from_attributes = True

class StageResponse(BaseModel):
    id: int
    name: str
    description: Optional[str]
    order: int
    class Config:
        from_attributes = True

class ProgressResponse(BaseModel):
    stage_id: int
    status: StageStatus
    updated_at: datetime
    class Config:
        from_attributes = True

class QuizResult(BaseModel):
    score: int
    passed: bool
