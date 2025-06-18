from fastapi import FastAPI, Request
from pydantic import BaseModel
from datetime import datetime
import psycopg2
import os

app = FastAPI()

DB_URL = os.getenv("DATABASE_URL", "dbname=telemetry user=postgres password=postgres host=telemetry-db")

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
        (data.timestamp, data.position, data.speed, data.status, datetime.utcnow())
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
