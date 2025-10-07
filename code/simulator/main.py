"""
Apollo 11 Astronaut Onboarding Simulator Service
Handles simulation requests and provides realistic training scenarios
"""
import os
import json
import time
import random
import asyncio
import logging
from datetime import datetime
from typing import Dict, Any, List
import redis
from pydantic import BaseModel
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Configuration
REDIS_URL = os.getenv("REDIS_URL", "redis://redis:6379")
SIMULATION_DELAY_MIN = int(os.getenv("SIMULATION_DELAY_MIN", "3"))
SIMULATION_DELAY_MAX = int(os.getenv("SIMULATION_DELAY_MAX", "8"))
SUCCESS_RATE = float(os.getenv("SUCCESS_RATE", "0.8"))

# Redis client
redis_client = redis.from_url(REDIS_URL)

# Simulation scenarios for each stage
SIMULATION_SCENARIOS = {
    1: {  # Physical Fitness Assessment
        "name": "Physical Fitness Assessment",
        "scenarios": [
            {
                "success": True,
                "message": "Excellent cardiovascular endurance! You passed the fitness test with flying colors.",
                "data": {"heart_rate": 72, "blood_pressure": "120/80", "endurance_score": 95}
            },
            {
                "success": False,
                "message": "Your fitness level needs improvement. Please focus on cardiovascular training.",
                "data": {"heart_rate": 95, "blood_pressure": "140/90", "endurance_score": 65}
            }
        ]
    },
    2: {  # Mental Health Screening
        "name": "Mental Health Screening",
        "scenarios": [
            {
                "success": True,
                "message": "Outstanding psychological resilience! You demonstrate excellent stress management skills.",
                "data": {"stress_level": "low", "cognitive_score": 92, "resilience_index": 88}
            },
            {
                "success": False,
                "message": "Additional stress management training recommended. Consider counseling sessions.",
                "data": {"stress_level": "high", "cognitive_score": 68, "resilience_index": 55}
            }
        ]
    },
    3: {  # Technical Knowledge Test
        "name": "Technical Knowledge Test",
        "scenarios": [
            {
                "success": True,
                "message": "Exceptional technical knowledge! You scored 95% on the spacecraft systems exam.",
                "data": {"test_score": 95, "areas_mastered": ["life_support", "navigation", "communication"]}
            },
            {
                "success": False,
                "message": "Technical knowledge needs improvement. Review spacecraft systems manual.",
                "data": {"test_score": 65, "areas_needing_work": ["life_support", "emergency_procedures"]}
            }
        ]
    },
    4: {  # Emergency Procedures Training
        "name": "Emergency Procedures Training",
        "scenarios": [
            {
                "success": True,
                "message": "Perfect emergency response! You handled the simulated crisis flawlessly.",
                "data": {"response_time": 45, "procedures_followed": 100, "team_coordination": "excellent"}
            },
            {
                "success": False,
                "message": "Emergency response needs work. Practice crisis scenarios more frequently.",
                "data": {"response_time": 120, "procedures_followed": 60, "team_coordination": "poor"}
            }
        ]
    },
    5: {  # Space Suit Operations
        "name": "Space Suit Operations",
        "scenarios": [
            {
                "success": True,
                "message": "Masterful EVA suit operation! You completed the spacewalk simulation successfully.",
                "data": {"suit_pressure": "stable", "oxygen_level": 98, "mobility_score": 92}
            },
            {
                "success": False,
                "message": "Space suit operation needs practice. Focus on pressure management and mobility.",
                "data": {"suit_pressure": "unstable", "oxygen_level": 85, "mobility_score": 65}
            }
        ]
    },
    6: {  # Zero Gravity Simulation
        "name": "Zero Gravity Simulation",
        "scenarios": [
            {
                "success": True,
                "message": "Excellent zero-g adaptation! You maintained perfect control in weightless conditions.",
                "data": {"adaptation_time": 15, "motion_sickness": "none", "task_completion": 100}
            },
            {
                "success": False,
                "message": "Zero-g adaptation challenging. Additional parabolic flight training recommended.",
                "data": {"adaptation_time": 45, "motion_sickness": "moderate", "task_completion": 70}
            }
        ]
    },
    7: {  # Mission Planning
        "name": "Mission Planning",
        "scenarios": [
            {
                "success": True,
                "message": "Outstanding mission planning! Your orbital calculations were precise and efficient.",
                "data": {"fuel_efficiency": 95, "timeline_accuracy": 98, "contingency_plans": "comprehensive"}
            },
            {
                "success": False,
                "message": "Mission planning needs refinement. Review orbital mechanics and fuel calculations.",
                "data": {"fuel_efficiency": 75, "timeline_accuracy": 80, "contingency_plans": "basic"}
            }
        ]
    },
    8: {  # Communication Protocols
        "name": "Communication Protocols",
        "scenarios": [
            {
                "success": True,
                "message": "Perfect communication! You maintained clear contact with ground control throughout.",
                "data": {"signal_clarity": 98, "protocol_adherence": 100, "response_time": 2.5}
            },
            {
                "success": False,
                "message": "Communication protocols need improvement. Practice radio procedures and timing.",
                "data": {"signal_clarity": 75, "protocol_adherence": 70, "response_time": 8.2}
            }
        ]
    },
    9: {  # Equipment Familiarization
        "name": "Equipment Familiarization",
        "scenarios": [
            {
                "success": True,
                "message": "Complete equipment mastery! You demonstrated expert knowledge of all systems.",
                "data": {"system_knowledge": 98, "troubleshooting": 95, "maintenance_skills": 92}
            },
            {
                "success": False,
                "message": "Equipment knowledge incomplete. Spend more time with system manuals and training.",
                "data": {"system_knowledge": 70, "troubleshooting": 65, "maintenance_skills": 60}
            }
        ]
    },
    10: {  # Mission Simulation
        "name": "Mission Simulation",
        "scenarios": [
            {
                "success": True,
                "message": "Mission simulation completed successfully! You're ready for real space missions.",
                "data": {"launch_success": True, "orbital_operations": "flawless", "landing_accuracy": 99}
            },
            {
                "success": False,
                "message": "Mission simulation revealed areas for improvement. Additional training required.",
                "data": {"launch_success": False, "orbital_operations": "challenging", "landing_accuracy": 75}
            }
        ]
    },
    11: {  # Final Certification
        "name": "Final Certification",
        "scenarios": [
            {
                "success": True,
                "message": "Congratulations! You have successfully completed astronaut training and are certified for space missions!",
                "data": {"overall_score": 96, "certification_level": "expert", "mission_ready": True}
            },
            {
                "success": False,
                "message": "Final certification not achieved. Additional training and practice required.",
                "data": {"overall_score": 75, "certification_level": "intermediate", "mission_ready": False}
            }
        ]
    }
}


class SimulationRequest(BaseModel):
    user_id: int
    stage_id: int
    attempt_number: int
    simulation_data: Dict[str, Any] = {}


class SimulationResponse(BaseModel):
    user_id: int
    stage_id: int
    attempt_number: int
    result: str  # "success" or "failure"
    message: str
    simulation_data: Dict[str, Any] = {}
    timestamp: datetime


def get_simulation_result(stage_id: int) -> Dict[str, Any]:
    """Get a simulation result for the given stage"""
    if stage_id not in SIMULATION_SCENARIOS:
        # Default scenario for unknown stages
        return {
            "success": random.random() < SUCCESS_RATE,
            "message": "Simulation completed with mixed results.",
            "data": {"stage_id": stage_id, "random_factor": random.randint(1, 100)}
        }
    
    stage_scenarios = SIMULATION_SCENARIOS[stage_id]["scenarios"]
    
    # Determine success based on success rate
    is_success = random.random() < SUCCESS_RATE
    
    # Filter scenarios by success/failure
    matching_scenarios = [s for s in stage_scenarios if s["success"] == is_success]
    
    if not matching_scenarios:
        # Fallback to any scenario
        matching_scenarios = stage_scenarios
    
    # Select random scenario
    selected_scenario = random.choice(matching_scenarios)
    
    return {
        "success": selected_scenario["success"],
        "message": selected_scenario["message"],
        "data": selected_scenario["data"]
    }


async def process_simulation_request(request_data: str):
    """Process a simulation request"""
    try:
        # Parse request
        request_dict = json.loads(request_data)
        request = SimulationRequest(**request_dict)
        
        logger.info(f"Processing simulation request for user {request.user_id}, stage {request.stage_id}")
        
        # Simulate processing time
        delay = random.uniform(SIMULATION_DELAY_MIN, SIMULATION_DELAY_MAX)
        await asyncio.sleep(delay)
        
        # Get simulation result
        result = get_simulation_result(request.stage_id)
        
        # Create response
        response = SimulationResponse(
            user_id=request.user_id,
            stage_id=request.stage_id,
            attempt_number=request.attempt_number,
            result="success" if result["success"] else "failure",
            message=result["message"],
            simulation_data=result["data"],
            timestamp=datetime.utcnow()
        )
        
        # Publish response to Redis
        response_data = response.model_dump_json()
        redis_client.publish("simulation_responses", response_data)
        
        logger.info(f"Simulation completed for user {request.user_id}, stage {request.stage_id}: {response.result}")
        
    except Exception as e:
        logger.error(f"Error processing simulation request: {e}")


def listen_for_requests():
    """Listen for simulation requests from Redis"""
    logger.info("Starting simulation service...")
    logger.info(f"Success rate: {SUCCESS_RATE * 100}%")
    logger.info(f"Simulation delay: {SIMULATION_DELAY_MIN}-{SIMULATION_DELAY_MAX} seconds")
    
    pubsub = redis_client.pubsub()
    pubsub.subscribe("simulation_requests")
    
    logger.info("Listening for simulation requests...")
    
    for message in pubsub.listen():
        if message["type"] == "message":
            # Process simulation request asynchronously
            asyncio.create_task(process_simulation_request(message["data"]))
    
    pubsub.close()


def health_check():
    """Simple health check"""
    try:
        redis_client.ping()
        return True
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        return False


if __name__ == "__main__":
    # Wait for Redis to be available
    max_retries = 30
    retry_count = 0
    
    while retry_count < max_retries:
        if health_check():
            logger.info("Redis connection established")
            break
        else:
            retry_count += 1
            logger.info(f"Waiting for Redis... (attempt {retry_count}/{max_retries})")
            time.sleep(2)
    else:
        logger.error("Failed to connect to Redis after maximum retries")
        exit(1)
    
    # Start listening for requests
    try:
        listen_for_requests()
    except KeyboardInterrupt:
        logger.info("Simulation service stopped")
    except Exception as e:
        logger.error(f"Simulation service error: {e}")
        exit(1)
