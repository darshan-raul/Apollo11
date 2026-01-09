# Core API

FastAPI-based Request Orchestrator and User Manager.

## Responsibilities
- Auth validation (Keycloak)
- Stage tracking
- Quiz orchestration

## Run
```bash
docker build -t core-api .
docker run -p 8000:8000 core-api
```
