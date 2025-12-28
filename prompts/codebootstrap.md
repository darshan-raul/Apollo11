# Apollo 11 Astronaut Onboarding Application - Implementation Prompt

## Objective
Create a cloud-native microservices application named **"Apollo 11 Astronaut Onboarding"**. This application is a simulation platform designed to teach Kubernetes concepts by guiding users through 11 stages of astronaut training.

## Architecture & Tech Stack

The application must be composed of the following microservices, each in its own directory within `code/`.

### 1. Frontend Service (`code/frontend`)
-   **Language**: Python
-   **Framework**: FastAPI
-   **Templating**: Jinja2 (Server-side rendering)
-   **Styling**: Vanilla CSS (Cyberpunk/Space theme - utilize dark modes, neon accents, glassmorphism).
-   **Dependency Manager**: `uv`
-   **Functionality**:
    -   User Registration/Login (Simple auth stored in Redis/DB).
    -   Dashboard showing the 11-stage progression.
    -   Stage details page with "Start Simulation" button.
    -   Polls Core API or displays real-time updates of simulation status.
    -   **Port**: 8000

### 2. Core API Service (`code/core-api`)
-   **Language**: Golang
-   **Dependencies**: `go.mod`
-   **Functionality**:
    -   REST API for Frontend interaction (User mgmt, Stage control).
    -   Manages application state in Postgres.
    -   Publishes simulation requests to Redis PubSub.
    -   Subscribes to simulation results from Redis PubSub and updates DB.
    -   **Port**: 8080

### 3. Simulator Service (`code/simulator`)
-   **Language**: Python
-   **Dependency Manager**: `uv`
-   **Logic**:
    -   Listens to Redis channel `simulation_requests`.
    -   Processes requests with a simulated delay (random 3-8s).
    -   Determines success/failure (80% success rate).
    -   Generates detailed, realistic telemetry data for each stage (e.g., "Heart Rate: 120bpm" for fitness stage, "Oxygen Levels: 98%" for EVA stage).
    -   Publishes results back to Redis channel `simulation_responses`.

### 4. Admin Dashboard (`code/admin-dashboard`)
-   **Language**: Python
-   **Framework**: Streamlit
-   **Dependency Manager**: `uv`
-   **Functionality**:
    -   Read-only view of system stats.
    -   Visualizations: User progress distribution, stage pass/fail rates, system health.
    -   Connects directly to Postgres and Redis for analytics.
    -   **Port**: 8501

### 5. Infrastructure Components
-   **Database**: PostgreSQL 15 (Persist users, stage progress, simulation logs).
-   **Message Broker**: Redis 7 (PubSub for service decoupling, Session store).

## Data Flow
1.  **User Action**: User clicks "Start Stage 1" on Frontend.
2.  **API Call**: Frontend sends POST request to Core API.
3.  **State Update**: Core API creates a "In Progress" record in Postgres.
4.  **Async Task**: Core API publishes `{user_id, stage_id}` to Redis `simulation_requests`.
5.  **Processing**: Simulator receives message, waits, calculates result (Pass/Fail).
6.  **Result**: Simulator publishes result to Redis `simulation_responses`.
7.  **Finalization**: Core API receives result, updates Postgres to "Completed" or "Failed".
8.  **Feedback**: Frontend polls API/reloads to show success message and unlock Stage 2.

## The 11 Stages
Implement logic regarding these 11 progressive stages:
1.  Physical Fitness Assessment
2.  Mental Health Screening
3.  Technical Knowledge Test
4.  Emergency Procedures Training
5.  Space Suit Operations
6.  Zero Gravity Simulation
7.  Mission Planning
8.  Communication Protocols
9.  Equipment Familiarization
10. Mission Simulation
11. Final Certification

## Deliverables

### 1. Source Code
Complete, runnable code for all 4 services in their respective folders.

### 2. Containerization
-   `Dockerfile` for each service (multistage builds where appropriate).
-   `devbox.json` for local shell environment (Go, Python, uv, kubectl, kind, docker).

### 3. Orchestration
-   `docker-compose.yml` for local development (spinning up all 4 services + Redis + Postgres).

### 4. Kubernetes Manifests (`code/k8s/`)
Detailed YAML manifests for deploying to a Kind cluster:
-   **Namespaces**: `apollo11`
-   **Deployments**: Replicas for each service.
-   **Services**: ClusterIP for internal comms, NodePort/LoadBalancer for external access.
-   **ConfigMaps/Secrets**: Handling vars like `DB_URL`, `REDIS_HOST`.
-   **Ingress**: Simple ingress rules (optional, can use NodePort for simplicity).

## Styling & UX
-   **Aesthetics**: High-end "Space Age" UI. Deep blues, purples, stars in background.
-   **Interactivity**: Loading bars during simulation, smooth transitions, confetti on success.