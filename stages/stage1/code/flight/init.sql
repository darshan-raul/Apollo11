-- Flight Service: airports + flights tables + seed data
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE IF NOT EXISTS airports (
    id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code     VARCHAR(5) UNIQUE NOT NULL,
    name     VARCHAR(100),
    city     VARCHAR(100),
    country  VARCHAR(100)
);

CREATE TABLE IF NOT EXISTS flights (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    flight_number    VARCHAR(20) UNIQUE NOT NULL,
    origin           VARCHAR(5) REFERENCES airports(code),
    destination      VARCHAR(5) REFERENCES airports(code),
    departure_time   TIMESTAMP NOT NULL,
    arrival_time     TIMESTAMP NOT NULL,
    total_capacity   INT NOT NULL,
    available_seats  INT NOT NULL,
    status           VARCHAR(20) DEFAULT 'SCHEDULED',
    created_at       TIMESTAMP DEFAULT NOW(),
    updated_at       TIMESTAMP DEFAULT NOW()
);

-- Seed airports (deterministic UUIDs)
INSERT INTO airports (id, code, name, city, country) VALUES
    ('11111111-1111-1111-1111-111111111111', 'BOM', 'Chhatrapati Shivaji Maharaj International', 'Mumbai', 'India'),
    ('22222222-2222-2222-2222-222222222222', 'DEL', 'Indira Gandhi International', 'New Delhi', 'India'),
    ('33333333-3333-3333-3333-333333333333', 'SIN', 'Changi Airport', 'Singapore', 'Singapore'),
    ('44444444-4444-4444-4444-444444444444', 'DXB', 'Dubai International', 'Dubai', 'UAE'),
    ('55555555-5555-5555-5555-555555555555', 'LHR', 'Heathrow Airport', 'London', 'UK'),
    ('66666666-6666-6666-6666-666666666666', 'JFK', 'John F. Kennedy International', 'New York', 'USA')
ON CONFLICT (code) DO NOTHING;

-- Seed flights: today + 30 days (deterministic UUIDs based on flight number)
-- AA101: BOM→SIN 08:00, AA102: SIN→BOM 20:00
-- AA201: DEL→DXB 09:30, AA202: DXB→DEL 22:00
-- AA301: BOM→LHR 01:00, AA401: DEL→JFK 02:00
INSERT INTO flights (id, flight_number, origin, destination, departure_time, arrival_time, total_capacity, available_seats, status) VALUES
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'AA101', 'BOM', 'SIN', (CURRENT_DATE + INTERVAL '0 hour' + TIME '08:00:00')::timestamp, (CURRENT_DATE + INTERVAL '0 hour' + TIME '14:30:00')::timestamp, 180, 180, 'SCHEDULED'),
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaabbb', 'AA102', 'SIN', 'BOM', (CURRENT_DATE + INTERVAL '0 hour' + TIME '20:00:00')::timestamp, (CURRENT_DATE + INTERVAL '0 hour' + TIME '23:30:00')::timestamp, 180, 180, 'SCHEDULED'),
    ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb', 'AA201', 'DEL', 'DXB', (CURRENT_DATE + INTERVAL '0 hour' + TIME '09:30:00')::timestamp, (CURRENT_DATE + INTERVAL '0 hour' + TIME '13:00:00')::timestamp, 220, 220, 'SCHEDULED'),
    ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbcc', 'AA202', 'DXB', 'DEL', (CURRENT_DATE + INTERVAL '0 hour' + TIME '22:00:00')::timestamp, (CURRENT_DATE + INTERVAL '0 hour' + TIME '02:30:00')::timestamp, 220, 220, 'SCHEDULED'),
    ('cccccccc-cccc-cccc-cccc-cccccccccc', 'AA301', 'BOM', 'LHR', (CURRENT_DATE + INTERVAL '0 hour' + TIME '01:00:00')::timestamp, (CURRENT_DATE + INTERVAL '0 hour' + TIME '10:00:00')::timestamp, 300, 300, 'SCHEDULED'),
    ('cccccccc-cccc-cccc-cccc-ccccccccccdd', 'AA401', 'DEL', 'JFK', (CURRENT_DATE + INTERVAL '0 hour' + TIME '02:00:00')::timestamp, (CURRENT_DATE + INTERVAL '0 hour' + TIME '14:00:00')::timestamp, 280, 280, 'SCHEDULED')
ON CONFLICT (flight_number) DO NOTHING;

-- Insert flights for next 30 days (same times, same routes)
INSERT INTO flights (flight_number, origin, destination, departure_time, arrival_time, total_capacity, available_seats, status)
SELECT
    flight_number,
    origin,
    destination,
    (CURRENT_DATE + n * INTERVAL '1 day' + TIME '08:00:00')::timestamp,
    (CURRENT_DATE + n * INTERVAL '1 day' + TIME '14:30:00')::timestamp,
    total_capacity,
    total_capacity,
    'SCHEDULED'
FROM (VALUES
    ('AA101', 'BOM', 'SIN', 180),
    ('AA102', 'SIN', 'BOM', 180),
    ('AA201', 'DEL', 'DXB', 220),
    ('AA202', 'DXB', 'DEL', 220),
    ('AA301', 'BOM', 'LHR', 300),
    ('AA401', 'DEL', 'JFK', 280)
) AS f(flight_number, origin, destination, total_capacity)
CROSS JOIN generate_series(1, 30) AS n
ON CONFLICT (flight_number) DO NOTHING;