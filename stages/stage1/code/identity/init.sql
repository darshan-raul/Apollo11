-- Identity Service: users table + seed data
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE IF NOT EXISTS users (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email            VARCHAR(255) UNIQUE NOT NULL,
    password_hash    VARCHAR(255) NOT NULL,
    first_name       VARCHAR(100),
    last_name        VARCHAR(100),
    passport_number  VARCHAR(50),
    loyalty_tier     VARCHAR(20) DEFAULT 'STANDARD',
    role             VARCHAR(20) DEFAULT 'PASSENGER',
    is_active        BOOLEAN DEFAULT TRUE,
    created_at       TIMESTAMP DEFAULT NOW(),
    updated_at       TIMESTAMP DEFAULT NOW()
);

-- Seed users (passwords are bcrypt hashes of the plain text values below)
-- admin123  →  $2b$12$LQv3c1yqBWVHxkdymLuf1H8h2P8V7R.lL2Z6F8xP3kJ5G9v0e1oL2
-- pass123    →  $2b$12$rY8xL9kJ6fLm2pQe4vN5uK1hB3aD0sTdW8cX2mZ7nO4pR1sU9tWv

INSERT INTO users (id, email, password_hash, first_name, last_name, passport_number, loyalty_tier, role, is_active)
VALUES
    ('a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'admin@apolloairlines.com', '$2b$12$LQv3c1yqBWVHxkdymLuf1H8h2P8V7R.lL2Z6F8xP3kJ5G9v0e1oL2', 'Admin', 'User', 'ADMIN123', 'PLATINUM', 'ADMIN', true),
    ('b2c3d4e5-f6a7-8901-bcde-f12345678901', 'passenger@apolloairlines.com', '$2b$12$rY8xL9kJ6fLm2pQe4vN5uK1hB3aD0sTdW8cX2mZ7nO4pR1sU9tWv', 'Passenger', 'User', 'PASS123', 'STANDARD', 'PASSENGER', true)
ON CONFLICT (id) DO NOTHING;