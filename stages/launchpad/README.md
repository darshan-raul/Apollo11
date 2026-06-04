---
title: "Launchpad — Docker Compose"
description: "Get Apollo Airlines running locally with Docker Compose. 10 components, stub code, seed data ready."
---

# Launchpad — Apollo Airlines

**Goal:** Run all 10 components locally using Docker Compose. Verify seed data is present, services respond correctly, and understand how containers communicate.

## What You'll Learn

- Multi-container Docker Compose setup with PostgreSQL and Redis
- Service networking via Docker DNS
- PostgreSQL initialization via `/docker-entrypoint-initdb.d/`
- Volume management for stateful services
- Multi-stage Dockerfile builds (no npm on host — frontend builds inside Docker)

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  Docker Compose (apollo-airlines network)                       │
│                                                                  │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐            │
│  │  frontend   │  │  identity   │  │   flight    │            │
│  │  (React)    │  │  (FastAPI)  │  │  (Go/Gin)   │            │
│  │  :3000      │  │  :8080      │  │  :8081      │            │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘            │
│         │                │                │                    │
│  ┌──────▼────────────────▼────────────────▼──────┐            │
│  │           booking         search    notification │            │
│  │           (Go/Gin)       (Go/Gin)  (Go/Gin)     │            │
│  │           :8082           :8083      :8084       │            │
│  └──────────────────────────────────────────────────┘            │
│                                                                  │
│  ┌──────────────────────────────────────────────────────┐       │
│  │  identity-db    flight-db    booking-db    redis     │       │
│  │  (postgres:15) (postgres:15) (postgres:15) (redis:7) │       │
│  │  :5432         :5432         :5432         :6379     │       │
│  └──────────────────────────────────────────────────────┘       │
└─────────────────────────────────────────────────────────────────┘
```

## Services (10 total)

| Service | Language | Port | Database | Purpose |
|---|---|---|---|---|
| frontend | React/Node | 3000 | — | SPA, served via NGINX |
| identity | Python/FastAPI | 8080 | identity-db | JWT auth, user profiles |
| flight | Go/Gin | 8081 | flight-db | Flight inventory, seat management |
| booking | Go/Gin | 8082 | booking-db | Reservations (flagship) |
| search | Go/Gin | 8083 | — | Flight search (no cache yet) |
| notification | Go/Gin | 8084 | — | Event fan-out |
| identity-db | PostgreSQL 15 | 5432 | — | users table |
| flight-db | PostgreSQL 15 | 5432 | — | airports + flights tables |
| booking-db | PostgreSQL 15 | 5432 | — | bookings table |
| redis | Redis 7 | 6379 | — | Notification queue |

## All Services Must Implement (from Day 1)

Every service has these endpoints — they exist from Launchpad, not added later:

| Endpoint | Purpose |
|---|---|
| `GET /healthz` | Liveness — process is alive |
| `GET /readyz` | Readiness — DB + downstream reachable |
| `GET /metrics` | Prometheus metrics (`http_requests_total`, `http_request_duration_ms`, `db_connections_active`) |

All services emit structured JSON logs:

```json
{
  "timestamp": "2025-01-15T10:23:00Z",
  "level": "INFO",
  "service": "booking-service",
  "trace_id": "abc123",
  "span_id": "def456",
  "message": "Booking created"
}
```

## Seed Data

Present from first `docker compose up`. No manual setup required.

**Airports (6):** BOM, DEL, SIN, DXB, LHR, JFK

**Flights (6, today + 30 days):**
| Flight | Route | Departure | Seats |
|---|---|---|---|
| AA101 | BOM → SIN | 08:00 | 180 |
| AA102 | SIN → BOM | 20:00 | 180 |
| AA201 | DEL → DXB | 09:30 | 220 |
| AA202 | DXB → DEL | 22:00 | 220 |
| AA301 | BOM → LHR | 01:00 | 300 |
| AA401 | DEL → JFK | 02:00 | 280 |

**Users:**
- `admin@apolloairlines.com` / `admin123` (ADMIN)
- `passenger@apolloairlines.com` / `pass123` (PASSENGER)

## Run It

```bash
cd stages/launchpad
docker compose up --build
```

Wait ~15s for PostgreSQL init scripts to complete, then verify:

```bash
# Check all services are up
curl http://localhost:8080/healthz
curl http://localhost:8081/healthz
curl http://localhost:8082/healthz
curl http://localhost:8083/healthz
curl http://localhost:8084/healthz

# Frontend
curl http://localhost:3000

# Login to get a JWT
curl -X POST http://localhost:8080/api/users/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@apolloairlines.com","password":"admin123"}'

# Search for flights
curl "http://localhost:8081/api/flights?origin=BOM&destination=SIN&date=2025-06-01"
```

## Key Files

```
stages/launchpad/
├── docker-compose.yml          # All 10 services
├── README.md                   # This file
└── code/
    ├── identity/               # Python/FastAPI — users, JWT
    │   ├── main.py
    │   ├── requirements.txt
    │   ├── Dockerfile
    │   └── init.sql            # users table + seed data
    ├── flight/                  # Go/Gin — flights, seats
    │   ├── main.go
    │   ├── go.mod
    │   ├── Dockerfile
    │   └── init.sql            # airports + flights tables + seed
    ├── booking/                 # Go/Gin — reservations
    │   ├── main.go
    │   ├── go.mod
    │   ├── Dockerfile
    │   └── init.sql            # bookings table
    ├── search/                  # Go/Gin — flight search (stateless)
    │   ├── main.go
    │   ├── go.mod
    │   └── Dockerfile
    ├── notification/            # Go/Gin — event fan-out
    │   ├── main.go
    │   ├── go.mod
    │   └── Dockerfile
    └── frontend/                # React SPA
        ├── src/
        ├── Dockerfile          # Multi-stage: node builds → nginx serves
        └── nginx.conf
```

## Docker Images Used

| Service | Image |
|---|---|
| Go services | `golang:1.22-alpine` |
| Python service | `python:3.12-slim` |
| Frontend build | `node:20-alpine` |
| Frontend serve | `nginx:alpine` |
| PostgreSQL | `postgres:15-alpine` |
| Redis | `redis:7-alpine` |

## Environment Variables

Each service reads from environment:

```yaml
# identity
DATABASE_URL=postgresql://postgres:postgres@identity-db:5432/identity
JWT_SECRET=apollo-airlines-dev-secret
PORT=8080

# flight
DATABASE_URL=postgresql://postgres:postgres@flight-db:5432/flight
PORT=8081

# booking
DATABASE_URL=postgresql://postgres:postgres@booking-db:5432/booking
FLIGHT_SERVICE_URL=http://flight:8081
IDENTITY_SERVICE_URL=http://identity:8080
NOTIFICATION_SERVICE_URL=http://notification:8084
JWT_SECRET=apollo-airlines-dev-secret
PORT=8082

# search
FLIGHT_SERVICE_URL=http://flight:8081
PORT=8083

# notification
REDIS_URL=redis://redis:6379
PORT=8084

# frontend
PORT=3000
```

## Ports Summary

| Service | Port | Access |
|---|---|---|
| frontend | 3000 | http://localhost:3000 |
| identity | 8080 | http://localhost:8080 |
| flight | 8081 | http://localhost:8081 |
| booking | 8082 | http://localhost:8082 |
| search | 8083 | http://localhost:8083 |
| notification | 8084 | http://localhost:8084 |

## Clean Up

```bash
docker compose down -v   # -v removes volumes (data reset)
docker compose down       # keep volumes
```

---

## What's Next

**Ignition:** Set up a local kind Kubernetes cluster. Then move to **Stage 1** to deploy all 10 components to Kubernetes using Deployments, ConfigMaps, Secrets, and Jobs.

**Before moving on, make sure you can answer:**
1. How does Docker Compose DNS work — how does `booking` resolve `flight`?
2. What happens if you run `docker compose up` before the PostgreSQL init scripts finish?
3. Why does the frontend Dockerfile use multi-stage builds?
4. How are the seed flights generated — are UUIDs deterministic or random?