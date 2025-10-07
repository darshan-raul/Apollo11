"""
Database models and utilities for Apollo 11 Astronaut Onboarding System
"""
import os
from sqlalchemy import create_engine, Column, Integer, String, DateTime, Boolean, Float, Text, ForeignKey, JSON
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker, relationship
from datetime import datetime
from typing import Optional

# Database configuration
DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://apollo11:apollo11@postgres:5432/apollo11")

Base = declarative_base()


class User(Base):
    __tablename__ = "users"
    
    id = Column(Integer, primary_key=True, index=True)
    username = Column(String(50), unique=True, index=True, nullable=False)
    email = Column(String(100), unique=True, index=True, nullable=False)
    full_name = Column(String(100), nullable=False)
    password_hash = Column(String(255), nullable=False)
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    
    # Relationships
    stage_progress = relationship("StageProgress", back_populates="user")


class Stage(Base):
    __tablename__ = "stages"
    
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(100), nullable=False)
    description = Column(Text, nullable=False)
    max_attempts = Column(Integer, default=3)
    created_at = Column(DateTime, default=datetime.utcnow)


class StageProgress(Base):
    __tablename__ = "stage_progress"
    
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    stage_id = Column(Integer, ForeignKey("stages.id"), nullable=False)
    status = Column(String(20), default="locked")  # locked, available, in_progress, completed, failed
    attempts = Column(Integer, default=0)
    completed_at = Column(DateTime, nullable=True)
    simulation_result = Column(String(20), nullable=True)  # success, failure
    simulation_data = Column(JSON, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    # Relationships
    user = relationship("User", back_populates="stage_progress")
    stage = relationship("Stage")


class SimulationLog(Base):
    __tablename__ = "simulation_logs"
    
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    stage_id = Column(Integer, ForeignKey("stages.id"), nullable=False)
    attempt_number = Column(Integer, nullable=False)
    result = Column(String(20), nullable=False)  # success, failure
    message = Column(Text, nullable=True)
    simulation_data = Column(JSON, nullable=True)
    timestamp = Column(DateTime, default=datetime.utcnow)
    
    # Relationships
    user = relationship("User")
    stage = relationship("Stage")


# Database engine and session
engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


def get_db():
    """Dependency to get database session"""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def init_database():
    """Initialize database tables"""
    Base.metadata.create_all(bind=engine)
    
    # Insert default stages if they don't exist
    db = SessionLocal()
    try:
        from .schemas import STAGES
        
        for stage_data in STAGES:
            existing_stage = db.query(Stage).filter(Stage.id == stage_data["id"]).first()
            if not existing_stage:
                stage = Stage(
                    id=stage_data["id"],
                    name=stage_data["name"],
                    description=stage_data["description"]
                )
                db.add(stage)
        
        db.commit()
    finally:
        db.close()
