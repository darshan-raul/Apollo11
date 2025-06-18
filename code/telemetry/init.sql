CREATE TABLE IF NOT EXISTS telemetry (
    id SERIAL PRIMARY KEY,
    timestamp TIMESTAMP,
    position FLOAT,
    speed FLOAT,
    status TEXT,
    received_at TIMESTAMP
);