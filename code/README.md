# Apollo 11 Astronaut Onboarding System

A comprehensive microservices-based application for astronaut training and onboarding with 11 progressive stages.

## 🚀 Architecture Overview

The system consists of 5 main microservices:

- **Frontend** (FastAPI + Modern UI) - User interface for astronauts
- **Core API** (Golang) - Business logic and orchestration
- **Simulator** (Python) - Training simulation engine
- **Admin Dashboard** (Streamlit) - Monitoring and analytics
- **Message Queue** (Redis) - Pub/sub communication
- **Database** (PostgreSQL) - Data persistence

## 🎯 11 Astronaut Onboarding Stages

1. **Physical Fitness Assessment** - Health and fitness evaluation
2. **Mental Health Screening** - Psychological readiness assessment
3. **Technical Knowledge Test** - Space systems and procedures
4. **Emergency Procedures Training** - Crisis response protocols
5. **Space Suit Operations** - EVA suit handling and maintenance
6. **Zero Gravity Simulation** - Weightlessness adaptation
7. **Mission Planning** - Flight planning and navigation
8. **Communication Protocols** - Ground control and crew communication
9. **Equipment Familiarization** - Spacecraft systems training
10. **Mission Simulation** - Full mission rehearsal
11. **Final Certification** - Complete readiness assessment

## 🛠️ Quick Start

### Prerequisites

- Docker and Docker Compose
- Kubernetes cluster (for K8s deployment)
- kubectl (for K8s deployment)
- [uv](https://docs.astral.sh/uv/) package manager (for local development)

### Local Development Setup

For local development of individual services:

1. **Install uv**:
   ```bash
   curl -LsSf https://astral.sh/uv/install.sh | sh
   ```

2. **Navigate to service directory** (e.g., frontend):
   ```bash
   cd frontend
   ```

3. **Install dependencies**:
   ```bash
   uv sync
   ```

4. **Activate virtual environment**:
   ```bash
   source .venv/bin/activate  # On Unix/macOS
   # or
   .venv\Scripts\activate     # On Windows
   ```

5. **Run the service**:
   ```bash
   uv run python main.py  # or appropriate command
   ```

### Docker Compose Deployment

1. **Clone and navigate to the project:**
   ```bash
   cd /home/darshan/projects/Apollo11/code
   ```

2. **Start all services:**
   ```bash
   docker-compose up -d
   ```

3. **Access the applications:**
   - Frontend: http://localhost:8000
   - Admin Dashboard: http://localhost:8501
   - Core API: http://localhost:8080/health

4. **Stop services:**
   ```bash
   docker-compose down
   ```

### Kubernetes Deployment

1. **Build Docker images:**
   ```bash
   # Build all images
   docker build -t apollo11-frontend ./frontend
   docker build -t apollo11-core-api ./core-api
   docker build -t apollo11-simulator ./simulator
   docker build -t apollo11-admin-dashboard ./admin-dashboard
   ```

2. **Deploy to Kubernetes:**
   ```bash
   kubectl apply -k ./k8s
   ```

3. **Check deployment status:**
   ```bash
   kubectl get pods -n apollo11
   kubectl get services -n apollo11
   ```

4. **Access via port-forward:**
   ```bash
   # Frontend
   kubectl port-forward -n apollo11 service/frontend 8000:8000
   
   # Admin Dashboard
   kubectl port-forward -n apollo11 service/admin-dashboard 8501:8501
   ```

## 📊 System Flow

1. **User Registration/Login** - Astronauts create accounts and authenticate
2. **Stage Selection** - Users can access available training stages
3. **Simulation Request** - Frontend sends simulation request to Core API
4. **Message Publishing** - Core API publishes request to Redis
5. **Simulation Processing** - Simulator service processes the request
6. **Result Publishing** - Simulator publishes results back to Redis
7. **Progress Update** - Core API updates user progress in database
8. **Stage Unlocking** - Next stage becomes available on success

## 🔧 Configuration

### Package Management

This project uses [uv](https://docs.astral.sh/uv/) for fast and reliable Python package management:

- **Faster than pip**: 10-100x faster dependency resolution
- **Lock files**: Reproducible builds with `uv.lock`
- **Modern tooling**: Built-in virtual environment management
- **Compatible**: Works with existing `pyproject.toml` files

### Environment Variables

| Service | Variable | Default | Description |
|---------|----------|---------|-------------|
| All | `DATABASE_URL` | `postgres://apollo11:apollo11@postgres:5432/apollo11` | PostgreSQL connection string |
| All | `REDIS_URL` | `redis://redis:6379` | Redis connection string |
| Core API | `JWT_SECRET` | `apollo11-secret-key` | JWT signing secret |
| Simulator | `SUCCESS_RATE` | `0.8` | Simulation success rate (80%) |
| Simulator | `SIMULATION_DELAY_MIN` | `3` | Minimum simulation delay (seconds) |
| Simulator | `SIMULATION_DELAY_MAX` | `8` | Maximum simulation delay (seconds) |

### Database Schema

The system uses PostgreSQL with the following main tables:

- `users` - User accounts and profiles
- `stages` - Training stage definitions
- `stage_progress` - User progress through stages
- `simulation_logs` - Detailed simulation history

## 📈 Monitoring and Analytics

The Admin Dashboard provides:

- **User Statistics** - Registration, activity, completion rates
- **Stage Analytics** - Performance metrics per stage
- **System Health** - Service status and connectivity
- **Real-time Monitoring** - Live simulation activity
- **Success Rate Analysis** - Historical performance trends

## 🔒 Security Considerations

- JWT-based authentication
- Password hashing (implement proper hashing in production)
- Database connection encryption
- Environment variable management
- Kubernetes secrets for sensitive data

## 🚀 Production Deployment

### Development Workflow

1. **Install uv**:
   ```bash
   curl -LsSf https://astral.sh/uv/install.sh | sh
   ```

2. **Set up development environment**:
   ```bash
   # For each service
   cd frontend
   uv sync --dev
   uv run pytest
   uv run black .
   ```

3. **Generate lock files**:
   ```bash
   uv lock  # Creates uv.lock for reproducible builds
   ```

4. **Build and test**:
   ```bash
   ./scripts/deploy.sh build
   ./scripts/deploy.sh deploy
   ```

### Security Checklist

- [ ] Change default passwords and secrets
- [ ] Enable SSL/TLS encryption
- [ ] Implement proper password hashing
- [ ] Set up monitoring and alerting
- [ ] Configure backup strategies
- [ ] Set resource limits and requests
- [ ] Enable network policies
- [ ] Set up log aggregation

### Scaling Considerations

- **Horizontal Scaling** - All services support multiple replicas
- **Database Scaling** - Consider read replicas for high load
- **Redis Clustering** - For high-throughput scenarios
- **Load Balancing** - Use ingress controllers for traffic distribution

## 🐛 Troubleshooting

### Common Issues

1. **Database Connection Failed**
   - Check PostgreSQL service status
   - Verify connection string
   - Check network connectivity

2. **Redis Connection Failed**
   - Check Redis service status
   - Verify Redis URL
   - Check Redis memory limits

3. **Simulation Not Working**
   - Check simulator service logs
   - Verify Redis pub/sub channels
   - Check Core API connectivity

### Logs and Debugging

```bash
# Docker Compose logs
docker-compose logs -f [service-name]

# Kubernetes logs
kubectl logs -n apollo11 deployment/[service-name] -f

# Check service health
curl http://localhost:8080/health  # Core API
curl http://localhost:8000/        # Frontend
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🏗️ Microservices Architecture

- **Frontend (FastAPI + Modern UI)**
  - Technology: Python FastAPI with Bootstrap 5 UI
  - Features: User registration, login, stage progression, real-time updates
  - Port: 8000
  - Authentication: JWT-based with Redis session management

- **Core API (Golang)**
  - Technology: Go with Gin framework
  - Features: Business logic, user management, stage orchestration
  - Port: 8080
  - Database: PostgreSQL integration
  - Messaging: Redis pub/sub for simulation requests

- **Simulator Service (Python)**
  - Technology: Python with Redis pub/sub
  - Features: Realistic training simulations with 80% success rate
  - Scenarios: 11 unique simulation scenarios per stage
  - Configurable: Success rate, delay timing, simulation data

- **Admin Dashboard (Streamlit)**
  - Technology: Python Streamlit with Plotly charts
  - Features: Real-time analytics, user statistics, system monitoring
  - Port: 8501
  - Analytics: User progress, stage completion rates, system health

- **Infrastructure**
  - Database: PostgreSQL with comprehensive schema
  - Message Queue: Redis for pub/sub communication
  - Containerization: Docker with multi-stage builds
  - Orchestration: Docker Compose + Kubernetes manifests

## 🔄 System Flow

1. User registers/logs in through FastAPI frontend
2. User selects available training stage
3. Frontend sends simulation request to Core API
4. Core API publishes request to Redis
5. Simulator processes request with realistic scenarios
6. Simulator publishes results back to Redis
7. Core API updates user progress in database
8. Next stage unlocks on successful completion