-- Apollo 11 Astronaut Onboarding Database Initialization
-- This script creates the database schema and initial data

-- Create users table
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    full_name VARCHAR(100) NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create stages table
CREATE TABLE IF NOT EXISTS stages (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    description TEXT NOT NULL,
    max_attempts INTEGER DEFAULT 3,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create stage_progress table
CREATE TABLE IF NOT EXISTS stage_progress (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    stage_id INTEGER REFERENCES stages(id) ON DELETE CASCADE,
    status VARCHAR(20) DEFAULT 'locked' CHECK (status IN ('locked', 'available', 'in_progress', 'completed', 'failed')),
    attempts INTEGER DEFAULT 0,
    completed_at TIMESTAMP NULL,
    simulation_result VARCHAR(20) CHECK (simulation_result IN ('success', 'failure')),
    simulation_data JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create simulation_logs table
CREATE TABLE IF NOT EXISTS simulation_logs (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    stage_id INTEGER REFERENCES stages(id) ON DELETE CASCADE,
    attempt_number INTEGER NOT NULL,
    result VARCHAR(20) NOT NULL CHECK (result IN ('success', 'failure')),
    message TEXT,
    simulation_data JSONB,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_stage_progress_user_id ON stage_progress(user_id);
CREATE INDEX IF NOT EXISTS idx_stage_progress_stage_id ON stage_progress(stage_id);
CREATE INDEX IF NOT EXISTS idx_stage_progress_status ON stage_progress(status);
CREATE INDEX IF NOT EXISTS idx_simulation_logs_user_id ON simulation_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_simulation_logs_stage_id ON simulation_logs(stage_id);
CREATE INDEX IF NOT EXISTS idx_simulation_logs_timestamp ON simulation_logs(timestamp);

-- Insert default stages
INSERT INTO stages (id, name, description, max_attempts) VALUES
(1, 'Physical Fitness Assessment', 'Basic health and fitness evaluation including cardiovascular endurance, strength, and flexibility tests.', 3),
(2, 'Mental Health Screening', 'Psychological readiness assessment including stress management and cognitive function tests.', 3),
(3, 'Technical Knowledge Test', 'Space systems and procedures knowledge assessment covering spacecraft operations and safety protocols.', 3),
(4, 'Emergency Procedures Training', 'Crisis response protocols including fire suppression, medical emergencies, and system failures.', 3),
(5, 'Space Suit Operations', 'EVA suit handling, maintenance, and operation procedures for extravehicular activities.', 3),
(6, 'Zero Gravity Simulation', 'Weightlessness adaptation training using parabolic flight and underwater simulation.', 3),
(7, 'Mission Planning', 'Flight planning and navigation including orbital mechanics and mission timeline management.', 3),
(8, 'Communication Protocols', 'Ground control and crew communication procedures including radio protocols and emergency channels.', 3),
(9, 'Equipment Familiarization', 'Spacecraft systems training including life support, power, and navigation systems.', 3),
(10, 'Mission Simulation', 'Full mission rehearsal including launch, orbital operations, and landing procedures.', 3),
(11, 'Final Certification', 'Complete readiness assessment and final evaluation for mission assignment.', 3)
ON CONFLICT (id) DO NOTHING;

-- Create a function to update the updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Create trigger to automatically update updated_at
CREATE TRIGGER update_stage_progress_updated_at 
    BEFORE UPDATE ON stage_progress 
    FOR EACH ROW 
    EXECUTE FUNCTION update_updated_at_column();

-- Insert sample users for testing (optional)
-- Note: In production, remove these sample users
INSERT INTO users (username, email, full_name, password_hash, is_active) VALUES
('neil_armstrong', 'neil.armstrong@nasa.gov', 'Neil Armstrong', 'password123', true),
('buzz_aldrin', 'buzz.aldrin@nasa.gov', 'Buzz Aldrin', 'password123', true),
('michael_collins', 'michael.collins@nasa.gov', 'Michael Collins', 'password123', true)
ON CONFLICT (username) DO NOTHING;

-- Initialize stage progress for sample users
-- This will be handled by the application when users register
-- But we can pre-populate for existing users
DO $$
DECLARE
    user_record RECORD;
    stage_record RECORD;
BEGIN
    FOR user_record IN SELECT id FROM users LOOP
        FOR stage_record IN SELECT id FROM stages ORDER BY id LOOP
            INSERT INTO stage_progress (user_id, stage_id, status)
            VALUES (
                user_record.id, 
                stage_record.id, 
                CASE WHEN stage_record.id = 1 THEN 'available' ELSE 'locked' END
            )
            ON CONFLICT (user_id, stage_id) DO NOTHING;
        END LOOP;
    END LOOP;
END $$;
