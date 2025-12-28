import os
import json
import time
import random
import asyncio
import logging
from datetime import datetime
from typing import Dict, Any
import redis
import signal
import sys

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger("simulator")

# Configuration
REDIS_URL = os.getenv("REDIS_URL", "redis://redis:6379/0")
SUCCESS_RATE = float(os.getenv("SUCCESS_RATE", "0.8"))
MIN_DELAY = 3
MAX_DELAY = 8

# Redis Client
try:
    redis_client = redis.from_url(REDIS_URL, decode_responses=True)
except Exception as e:
    logger.error(f"Failed to connect to Redis: {e}")
    sys.exit(1)

# Simulation Scenarios (11 Stages)
SCENARIOS = {
    1: {"name": "Physical Fitness", "telemetry": lambda: {"heart_rate": random.randint(60, 160), "bp": f"{random.randint(110,140)}/{random.randint(70,90)}", "stamina": random.randint(80, 100)}},
    2: {"name": "Mental Health", "telemetry": lambda: {"stress_index": random.uniform(0.1, 0.5), "focus_score": random.randint(85, 99)}},
    3: {"name": "Technical Knowledge", "telemetry": lambda: {"score": random.randint(70, 100), "modules_completed": 5}},
    4: {"name": "Emergency Procedures", "telemetry": lambda: {"reaction_time_ms": random.randint(200, 500), "errors": 0}},
    5: {"name": "Space Suit Ops", "telemetry": lambda: {"suit_pressure_psi": 4.3, "o2_level": random.randint(95, 100)}},
    6: {"name": "Zero Gravity", "telemetry": lambda: {"nausea_index": random.randint(0, 2), "coordination": "high"}},
    7: {"name": "Mission Planning", "telemetry": lambda: {"fuel_efficiency": random.uniform(0.9, 1.0), "trajectory_error": 0.001}},
    8: {"name": "Comms Protocols", "telemetry": lambda: {"latency_ms": random.randint(50, 200), "signal_strength": "strong"}},
    9: {"name": "Equipment Fam", "telemetry": lambda: {"tools_mastered": 10, "safety_violations": 0}},
    10: {"name": "Mission Sim", "telemetry": lambda: {"mission_success_prob": 0.99, "anomalies": []}},
    11: {"name": "Final Cert", "telemetry": lambda: {"board_approval": "unanimous", "ready_for_flight": True}},
}

def process_simulation(data: Dict[str, Any]):
    user_id = data.get("user_id")
    stage_id = data.get("stage_id")
    attempt = data.get("attempt_number", 1)

    logger.info(f"Starting simulation for User {user_id} Stage {stage_id} Attempt {attempt}")

    # 1. Delay
    delay = random.uniform(MIN_DELAY, MAX_DELAY)
    time.sleep(delay)

    # 2. Determine Success
    # Simple logic: 80% success
    is_success = random.random() < SUCCESS_RATE
    result = "success" if is_success else "failure"

    # 3. Generate Telemetry
    stage_info = SCENARIOS.get(stage_id, {"name": "Unknown", "telemetry": lambda: {}})
    telemetry = stage_info["telemetry"]()
    
    message = f"Stage {stage_id} ({stage_info['name']}) "
    if is_success:
        message += "passed successfully."
    else:
        message += "failed. Please try again."

    # 4. Create Response
    response = {
        "user_id": user_id,
        "stage_id": stage_id,
        "result": result,
        "message": message,
        "simulation_data": telemetry,
        "timestamp": datetime.utcnow().isoformat()
    }

    # 5. Publish
    try:
        redis_client.publish("simulation_responses", json.dumps(response))
        logger.info(f"Completed simulation for User {user_id} Stage {stage_id}: {result}")
    except Exception as e:
        logger.error(f"Failed to publish result: {e}")

def main():
    logger.info("Simulator Service Started")
    pubsub = redis_client.pubsub()
    pubsub.subscribe("simulation_requests")

    for message in pubsub.listen():
        if message["type"] == "message":
            try:
                data = json.loads(message["data"])
                # In a real app, this should be async or threaded to not block
                process_simulation(data) 
            except json.JSONDecodeError:
                logger.error("Invalid JSON received")
            except Exception as e:
                logger.error(f"Error processing message: {e}")

if __name__ == "__main__":
    main()
