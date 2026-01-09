-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Create Schemas
CREATE SCHEMA IF NOT EXISTS core;
CREATE SCHEMA IF NOT EXISTS quiz;
CREATE SCHEMA IF NOT EXISTS audit;
CREATE SCHEMA IF NOT EXISTS keycloak;

-- core.users
CREATE TABLE IF NOT EXISTS core.users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    keycloak_id TEXT NOT NULL UNIQUE,
    email TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- core.stages
CREATE TABLE IF NOT EXISTS core.stages (
    id INT PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT,
    "order" INT NOT NULL
);

-- core.user_stage_progress
CREATE TYPE core.stage_status AS ENUM ('locked', 'in_progress', 'completed');
CREATE TABLE IF NOT EXISTS core.user_stage_progress (
    user_id UUID REFERENCES core.users(id),
    stage_id INT REFERENCES core.stages(id),
    status core.stage_status DEFAULT 'locked',
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, stage_id)
);

-- quiz.quiz_questions
CREATE TABLE IF NOT EXISTS quiz.quiz_questions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    stage_id INT REFERENCES core.stages(id),
    question TEXT NOT NULL,
    options JSONB NOT NULL,
    correct_answer TEXT NOT NULL
);

-- quiz.quiz_attempts
-- Note: prompt says id UUID. user_id UUID.
-- We need to reference core.users(id).
CREATE TABLE IF NOT EXISTS quiz.quiz_attempts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES core.users(id),
    stage_id INT REFERENCES core.stages(id),
    score INT NOT NULL,
    passed BOOLEAN NOT NULL,
    attempted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Seed Stages (1-11) as per prompt
INSERT INTO core.stages (id, name, description, "order") VALUES
(1, 'Liftoff', 'Containers & Local Development', 1),
(2, 'Stage 1: It Begins', 'Kubernetes Barebones', 2),
(3, 'Stage 2: Structural Integrity', 'Best Practices', 3),
(4, 'Stage 3: Persistent Journey', 'Storage Deep Dive', 4),
(5, 'Stage 4: Orbit Control', 'Networking in Depth', 5),
(6, 'Stage 5: Modular Payloads', 'Packaging and Extensibility', 6),
(7, 'Stage 6: Mission Control', 'Monitoring & Debugging', 7),
(8, 'Stage 7: Flight Automation', 'CI/CD and Workflows', 8),
(9, 'Stage 8: Secure Docking', 'Kubernetes Security', 9),
(10, 'Stage 9: Adaptive Thrust', 'Autoscaling & Optimization', 10),
(11, 'Stage 10: Contingency Mode', 'Backup, Upgrades, Chaos', 11)
ON CONFLICT (id) DO NOTHING;

-- Seed Quiz Questions for Stage 1 (ID=1)
INSERT INTO quiz.quiz_questions (stage_id, question, options, correct_answer) VALUES
(1, 'Which command lists running containers?', '["docker list", "docker ps", "docker run", "docker images"]', 'docker ps'),
(1, 'What is the PID 1 process in a container?', '["The entrypoint process", "systemd", "root", "bash"]', 'The entrypoint process'),
(1, 'Which flag runs a container in background?', '["-d", "-b", "--hidden", "-bg"]', '-d'),
(1, 'What is a Docker image?', '["A running instance", "A read-only template", "A virtual machine", "A filesystem"]', 'A read-only template'),
(1, 'How do you stop a container?', '["docker kill", "docker stop", "docker end", "docker halt"]', 'docker stop');
