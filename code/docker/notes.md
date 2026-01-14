# Apollo 11 Docker & Code Analysis Notes

## Overview
The `code/docker` directory acts as a monorepo setup for the Apollo 11 platform, containing the source code and Docker build context for 4 main services plus infrastructure components.

**Services:**
- **Core API (`core-api`)**: FastAPI (Python)
- **Quiz Service (`quiz-service`)**: Go (Fiber)
- **Portal (`portal`)**: React/Vite (Node -> Nginx)
- **Admin Dashboard (`admin-dashboard`)**: Streamlit (Python)
- **Infrastructure**: Postgres 15, Keycloak 23, Dozzle (logging)

## Service Breakdown

### 1. Docker Compose (`compose.yml`)
- **Structure**: Defines 6 services + 1 tool (`dozzle`).
- **Networking**: Single bridge network `apollo-net`.
- **Volumes**:
  - `postgres-data` for database persistence.
  - Mounts `./database/migrations` to Postgres init.
  - Mounts `./keycloak/realm-export.json` to Keycloak import.
- **Observations**:
  - **Secrets**: Passwords are hardcoded (`postgres`, `admin`).
  - **Healthchecks**: Missing. Services rely on `depends_on` order but not readiness.
  - **Restarts**: Inconsistent usage (only Keycloak has `restart: always`).

### 2. Core API
- **Stack**: Python 3.12-slim, FastAPI 0.109.0, SQLAlchemy 2.0, Pydantic 2.0.
- **Dockerfile**: Basic single-stage.
  - *Risk*: Runs as `root` user by default.
  - *Good*: Uses `pip --no-cache-dir`.

### 3. Quiz Service
- **Stack**: Go 1.22, Fiber v2, PGX v5.
- **Dockerfile**:
  - *Good*: Multi-stage build (Builder -> Scratch).
  - *Good*: `CGO_ENABLED=0` and small footprint.

### 4. Portal
- **Stack**: Node 20-alpine (build) -> Nginx alpine (runtime).
- **Configuration**:
  - Uses `VITE_*` build args. These are baked into the static assets at build time.
  - *Note*: `VITE_KEYCLOAK_URL` and `VITE_API_URL` point to `localhost`. This assumes the user's browser relies on port forwarding (e.g., `8081` and `8087` mapped in Compose).
- **Dockerfile**: Standard 2-stage build.

### 5. Admin Dashboard
- **Stack**: Python 3.12-slim, Streamlit 1.31.
- **Dockerfile**: Basic single-stage. Runs as root.

---

## Upgrade & Improvement Plan

### High Priority (Security & Reliability)
1.  **Implement Non-Root Users**: Update Python Dockerfiles (`core-api`, `admin-dashboard`) to create and switch to a non-root user for security.
2.  **Secret Management**: Move hardcoded credentials from `compose.yml` to a `.env` file and use `${VAR}` substitution.
3.  **Healthchecks**: Add `healthcheck` blocks to `postgres`, `keycloak`, and services. Update `depends_on` to use `condition: service_healthy`. This prevents race conditions on startup.

### Medium Priority (Architecture & Ops)
4.  **Runtime Configuration for Portal**: Currently, changing an API URL requires rebuilding the Portal image. Implement a runtime config loading strategy (e.g., `env.sh` script entrypoint that writes `window.env` to `index.html`) so the same image can be deployed to different environments (dev/prod) just by changing Compose env vars.
5.  **Multistage Python Builds**: Use multi-stage builds for Python services to reduce image size (copying only venv/site-packages).
6.  **Dependency Pinning**: Ensure `requirements.txt` and `go.mod` dependencies are pinned to specific versions (currently they are, but check for updates).
7.  **Keycloak Production config**: `start-dev` is used. For a "real" setup, switch to `start` with optimized build options.

### Low Priority (Housekeeping)
8.  **Context Optimization**: Ensure `.dockerignore` files are present in each service directory to prevent copying `node_modules`, `__pycache__`, or `.git` into the build context.
9.  **Standardize Logging**: Ensure all services emit JSON logs or structured logs for better ingestion (optional, Dozzle handles stdout well enough for dev).
