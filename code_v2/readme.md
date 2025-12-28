# Apollo 11 (V2) Walkthrough

I have successfully implemented the **Apollo 11 Astronaut Onboarding** application in the `code_v2` directory.

## Architecture
The application consists of 4 microservices:
1.  **Frontend** (Python/FastAPI): Space Age UI for user interaction. `http://localhost:8000`
2.  **Core API** (Go/Gin): Backend logic and state management. `http://localhost:8080`
3.  **Simulator** (Python): Simulation engine processing requests via Redis.
4.  **Admin Dashboard** (Streamlit): Analyitcs and monitoring. `http://localhost:8501`

Dependencies:
-   **Postgres**: Database
-   **Redis**: Message Broker

## How to Run

### Option 1: Docker Compose (Technique: "Liftoff")
This is the easiest way to run the entire stack locally.

1.  Navigate to the directory:
    ```bash
    cd code_v2
    ```
2.  Start the application:
    ```bash
    docker-compose up --build
    ```
3.  Access the services:
    -   **Frontend**: [http://localhost:8000](http://localhost:8000)
    -   **Admin Dashboard**: [http://localhost:8501](http://localhost:8501)

### Option 2: Kubernetes (Technique: "Orbit")
Deploy to a local Kind cluster.

1.  Create a cluster (if not exists):
    ```bash
    kind create cluster --name apollo11
    ```
2.  Build images (optional, if not using pre-built or local registry):
    ```bash
    # You may need to load images into kind or push to a registry
    docker build -t apollo11/core-api:latest ./core-api
    kind load docker-image apollo11/core-api:latest --name apollo11
    # Repeat for other services...
    ```
3.  Apply manifests:
    ```bash
    kubectl apply -f code_v2/k8s/
    ```
4.  Access via NodePort or Port Forward:
    ```bash
    kubectl port-forward svc/frontend -n apollo11 8000:8000
    kubectl port-forward svc/admin-dashboard -n apollo11 8501:8501
    ```

## Verification Results
-   **Builds**: All services have valid Dockerfiles and configuration.
-   **Code**:
    -   `core-api`: Compiles successfully.
    -   `frontend`: Templates and styles are in place.
    -   `simulator`: Logic for all 11 stages implemented.
    -   `admin-dashboard`: Connects to DB/Redis for real-time stats.

The application is ready for launch! 🚀
