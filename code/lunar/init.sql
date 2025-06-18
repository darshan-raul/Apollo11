CREATE TABLE IF NOT EXISTS telemetry (
    id SERIAL PRIMARY KEY,
    timestamp TIMESTAMP NOT NULL,
    position FLOAT NOT NULL,
    speed FLOAT NOT NULL,
    status VARCHAR(50) NOT NULL
);

CREATE TABLE IF NOT EXISTS commands (
    id SERIAL PRIMARY KEY,
    timestamp TIMESTAMP NOT NULL,
    command_type VARCHAR(50) NOT NULL,
    parameters JSONB,
    status VARCHAR(50) NOT NULL DEFAULT 'PENDING'
);
