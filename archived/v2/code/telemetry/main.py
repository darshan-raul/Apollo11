from fastapi import FastAPI, Request
from pydantic import BaseModel
from datetime import datetime, timezone
import psycopg2
import os

app = FastAPI()

DB_NAME = os.getenv("DB_NAME", "telemetry")
DB_USER = os.getenv("DB_USER", "postgres")
DB_PASSWORD = os.getenv("DB_PASSWORD", "postgres")
DB_HOST = os.getenv("DB_HOST", "telemetry-postgres")
DB_PORT = os.getenv("DB_PORT", "5432")
DB_URL = f"dbname={DB_NAME} user={DB_USER} password={DB_PASSWORD} host={DB_HOST} port={DB_PORT}"

def get_db():
    return psycopg2.connect(DB_URL)

class Telemetry(BaseModel):
    timestamp: str
    position: float
    speed: float
    status: str

@app.post("/input")
async def input_telemetry(data: Telemetry):
    conn = get_db()
    cur = conn.cursor()
    cur.execute(
        "INSERT INTO telemetry (timestamp, position, speed, status, received_at) VALUES (%s, %s, %s, %s, %s)",
        (data.timestamp, data.position, data.speed, data.status, datetime.now(timezone.utc))
    )
    conn.commit()
    cur.close()
    conn.close()
    return {"status": "ok"}

@app.get("/data")
def get_data():
    conn = get_db()
    cur = conn.cursor()
    cur.execute("SELECT timestamp, position, speed, status, received_at FROM telemetry ORDER BY received_at DESC")
    rows = cur.fetchall()
    cur.close()
    conn.close()
    return {"data": rows}

@app.get("/health")
def health():
    return {"status": "OK"}

@app.get("/ready")
def ready():
    return {"status": "READY"}

@app.get("/started")
def started():
    return {"status": "STARTED"}
