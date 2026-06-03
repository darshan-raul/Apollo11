---
title: "Stage 0: Liftoff — Docker Compose"
description: "Get the application running locally with Docker Compose. No Kubernetes yet."
---

# Stage 0: Liftoff

**Goal:** Get the Library Management System running locally using Docker Compose.

## What You'll Learn

- Multi-container Docker Compose setup
- Service networking and dependencies
- Database initialization with init scripts
- Volume management for stateful services
- Development vs production Dockerfile patterns

## Services (11 total)

| Service | Image | Port | Database |
|---------|-------|------|----------|
| frontend | Go/Gin | 3000 | — |
| auth | Python/FastAPI | 8080 | auth-postgres (5432) |
| catalog | Go/Gin | 8081 | catalog-postgres (5432) |
| catalog-redis | Redis 7 | 6379 | — |
| circulation | Go/Gin | 8082 | circulation-postgres (5432) |
| notification | Go/Gin | 8083 | notification-redis (6380) |
| fines | Go/Gin | 8084 | SQLite on volume |

## Run It

```bash
cd stages/launchpad
docker compose up -d
```

Wait ~10s for databases to initialize, then test:

```bash
curl http://localhost:3000
curl http://localhost:8080/health
curl http://localhost:8081/health
```

## Key Files

```
stages/launchpad/
├── docker-compose.yml        # All 11 services
└── code/
    ├── auth/                 # FastAPI — JWT auth
    ├── catalog/              # Go/Gin — book search
    ├── circulation/          # Go/Gin — loans/reservations
    ├── notification/         # Go/Gin — email notifications
    ├── fines/                # Go/Gin — fine calculations
    └── frontend/             # Go/Gin — web UI
```

## Clean Up

```bash
docker compose down -v   # -v removes volumes
```