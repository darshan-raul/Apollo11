"""
Shared data schemas for Apollo 11 Astronaut Onboarding System
"""
from pydantic import BaseModel, Field
from typing import Optional, List, Dict, Any
from datetime import datetime
from enum import Enum


class StageStatus(str, Enum):
    LOCKED = "locked"
    AVAILABLE = "available"
    IN_PROGRESS = "in_progress"
    COMPLETED = "completed"
    FAILED = "failed"


class SimulationResult(str, Enum):
    SUCCESS = "success"
    FAILURE = "failure"


class User(BaseModel):
    id: Optional[int] = None
    username: str = Field(..., min_length=3, max_length=50)
    email: str = Field(..., regex=r'^[^@]+@[^@]+\.[^@]+$')
    full_name: str = Field(..., min_length=2, max_length=100)
    created_at: Optional[datetime] = None
    is_active: bool = True


class UserCreate(BaseModel):
    username: str = Field(..., min_length=3, max_length=50)
    email: str = Field(..., regex=r'^[^@]+@[^@]+\.[^@]+$')
    full_name: str = Field(..., min_length=2, max_length=100)
    password: str = Field(..., min_length=6)


class UserLogin(BaseModel):
    username: str
    password: str


class Stage(BaseModel):
    id: int
    name: str
    description: str
    status: StageStatus
    completed_at: Optional[datetime] = None
    attempts: int = 0
    max_attempts: int = 3


class StageProgress(BaseModel):
    user_id: int
    stage_id: int
    status: StageStatus
    attempts: int = 0
    completed_at: Optional[datetime] = None
    simulation_result: Optional[SimulationResult] = None
    simulation_data: Optional[Dict[str, Any]] = None


class SimulationRequest(BaseModel):
    user_id: int
    stage_id: int
    attempt_number: int
    simulation_data: Optional[Dict[str, Any]] = None


class SimulationResponse(BaseModel):
    user_id: int
    stage_id: int
    attempt_number: int
    result: SimulationResult
    message: str
    simulation_data: Optional[Dict[str, Any]] = None
    timestamp: datetime


class StageUnlockRequest(BaseModel):
    user_id: int
    stage_id: int


class UserStats(BaseModel):
    user_id: int
    username: str
    full_name: str
    total_stages: int
    completed_stages: int
    current_stage: int
    total_attempts: int
    success_rate: float
    last_activity: Optional[datetime] = None


class SystemStats(BaseModel):
    total_users: int
    active_users: int
    total_simulations: int
    success_rate: float
    average_completion_time: Optional[float] = None
    stage_completion_stats: Dict[int, int]


# Redis message types
class RedisMessage(BaseModel):
    type: str
    data: Dict[str, Any]
    timestamp: datetime


class SimulationMessage(RedisMessage):
    type: str = "simulation_request"
    data: SimulationRequest


class SimulationResponseMessage(RedisMessage):
    type: str = "simulation_response"
    data: SimulationResponse


# Stage definitions
STAGES = [
    {
        "id": 1,
        "name": "Physical Fitness Assessment",
        "description": "Basic health and fitness evaluation including cardiovascular endurance, strength, and flexibility tests."
    },
    {
        "id": 2,
        "name": "Mental Health Screening",
        "description": "Psychological readiness assessment including stress management and cognitive function tests."
    },
    {
        "id": 3,
        "name": "Technical Knowledge Test",
        "description": "Space systems and procedures knowledge assessment covering spacecraft operations and safety protocols."
    },
    {
        "id": 4,
        "name": "Emergency Procedures Training",
        "description": "Crisis response protocols including fire suppression, medical emergencies, and system failures."
    },
    {
        "id": 5,
        "name": "Space Suit Operations",
        "description": "EVA suit handling, maintenance, and operation procedures for extravehicular activities."
    },
    {
        "id": 6,
        "name": "Zero Gravity Simulation",
        "description": "Weightlessness adaptation training using parabolic flight and underwater simulation."
    },
    {
        "id": 7,
        "name": "Mission Planning",
        "description": "Flight planning and navigation including orbital mechanics and mission timeline management."
    },
    {
        "id": 8,
        "name": "Communication Protocols",
        "description": "Ground control and crew communication procedures including radio protocols and emergency channels."
    },
    {
        "id": 9,
        "name": "Equipment Familiarization",
        "description": "Spacecraft systems training including life support, power, and navigation systems."
    },
    {
        "id": 10,
        "name": "Mission Simulation",
        "description": "Full mission rehearsal including launch, orbital operations, and landing procedures."
    },
    {
        "id": 11,
        "name": "Final Certification",
        "description": "Complete readiness assessment and final evaluation for mission assignment."
    }
]
