from fastapi import FastAPI, Request
import requests
import os
import logging
from pydantic import BaseModel
from typing import Any, Dict, Optional
from datetime import datetime

app = FastAPI()

LUNAR_MODULE_URL = os.getenv("LUNAR_MODULE_URL", "http://lunar-module:8080/command")

logging.basicConfig(level=logging.INFO)

class Command(BaseModel):
    id: Optional[int] = None
    timestamp: Optional[datetime] = None
    command_type: str
    parameters: Optional[Any] = None
    status: Optional[str] = None

@app.get("/health")
def health():
    return {"status": "OK"}

@app.get("/ready")
def ready():
    return {"status": "READY"}

@app.get("/started")
def started():
    return {"status": "STARTED"}

@app.post("/dispatch")
async def dispatch_command(command: Command):
    logging.info(f"Received dispatch request: {command}")
    # Relay to lunar module
    resp = requests.post(LUNAR_MODULE_URL, json=command.dict(exclude_none=True))
    logging.info(f"Lunar module response: {resp.status_code} {resp.text}")
    return {"status": "relayed", "lunar_module_response": resp.json()}
