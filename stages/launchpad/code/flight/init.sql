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
    flight_number    VARCHAR(20) NOT NULL,
    origin           VARCHAR(5) REFERENCES airports(code),
    destination      VARCHAR(5) REFERENCES airports(code),
    departure_time   TIMESTAMP NOT NULL,
    arrival_time     TIMESTAMP NOT NULL,
    total_capacity   INT NOT NULL,
    available_seats  INT NOT NULL,
    status           VARCHAR(20) DEFAULT 'SCHEDULED',
    created_at       TIMESTAMP DEFAULT NOW(),
    updated_at       TIMESTAMP DEFAULT NOW(),
    UNIQUE (flight_number, departure_time)
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

-- Seed flights: six routes a day for today + 30 days (186 rows).
-- Today's rows get deterministic UUIDs so labs and verifiers can address them.
-- An arrival time at or before the departure time means the flight lands the
-- next day (AA202 departs 22:00 and arrives 02:30).
INSERT INTO flights (id, flight_number, origin, destination, departure_time, arrival_time, total_capacity, available_seats, status)
SELECT
    CASE WHEN n = 0 THEN f.id ELSE gen_random_uuid() END,
    f.flight_number,
    f.origin,
    f.destination,
    (CURRENT_DATE + n * INTERVAL '1 day' + f.dep_time)::timestamp,
    (CURRENT_DATE + n * INTERVAL '1 day' + f.arr_time
        + CASE WHEN f.arr_time <= f.dep_time THEN INTERVAL '1 day' ELSE INTERVAL '0' END)::timestamp,
    f.total_capacity,
    f.total_capacity,
    'SCHEDULED'
FROM (VALUES
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid, 'AA101', 'BOM', 'SIN', TIME '08:00:00', TIME '14:30:00', 180),
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaabb'::uuid, 'AA102', 'SIN', 'BOM', TIME '20:00:00', TIME '23:30:00', 180),
    ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'::uuid, 'AA201', 'DEL', 'DXB', TIME '09:30:00', TIME '13:00:00', 220),
    ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbcc'::uuid, 'AA202', 'DXB', 'DEL', TIME '22:00:00', TIME '02:30:00', 220),
    ('cccccccc-cccc-cccc-cccc-cccccccccccc'::uuid, 'AA301', 'BOM', 'LHR', TIME '01:00:00', TIME '10:00:00', 300),
    ('cccccccc-cccc-cccc-cccc-ccccccccccdd'::uuid, 'AA401', 'DEL', 'JFK', TIME '02:00:00', TIME '14:00:00', 280)
) AS f(id, flight_number, origin, destination, dep_time, arr_time, total_capacity)
CROSS JOIN generate_series(0, 30) AS n
ON CONFLICT DO NOTHING;
