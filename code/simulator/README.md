# Apollo 11 Simulator Service

Python-based simulation engine for the Apollo 11 Astronaut Onboarding System. Handles training simulation requests and provides realistic training scenarios.

## Features

- Redis pub/sub message processing
- 11 unique simulation scenarios per training stage
- Configurable success rates and timing
- Realistic astronaut training simulations
- Asynchronous processing with asyncio

## Development Setup

### Prerequisites

- Python 3.11+
- [uv](https://docs.astral.sh/uv/) package manager
- Redis server

### Installation

1. **Install uv** (if not already installed):
   ```bash
   curl -LsSf https://astral.sh/uv/install.sh | sh
   ```

2. **Install dependencies**:
   ```bash
   uv sync
   ```

3. **Activate virtual environment**:
   ```bash
   source .venv/bin/activate  # On Unix/macOS
   # or
   .venv\Scripts\activate     # On Windows
   ```

### Running the Application

```bash
# Run the simulator
uv run python main.py

# Or using the script
uv run apollo11-simulator
```

### Development Commands

```bash
# Install development dependencies
uv sync --dev

# Run tests
uv run pytest

# Run tests with coverage
uv run pytest --cov

# Run tests without Redis (unit tests only)
uv run pytest -m "not redis"

# Format code
uv run black .
uv run isort .

# Type checking
uv run mypy .

# Linting
uv run flake8 .
```

## Environment Variables

Create a `.env` file in the simulator directory:

```env
REDIS_URL=redis://redis:6379
SIMULATION_DELAY_MIN=3
SIMULATION_DELAY_MAX=8
SUCCESS_RATE=0.8
```

## Configuration

### Simulation Parameters

- `SIMULATION_DELAY_MIN`: Minimum simulation delay in seconds (default: 3)
- `SIMULATION_DELAY_MAX`: Maximum simulation delay in seconds (default: 8)
- `SUCCESS_RATE`: Success rate for simulations (default: 0.8 = 80%)

### Redis Configuration

- `REDIS_URL`: Redis connection URL (default: redis://redis:6379)

## Simulation Scenarios

The simulator includes 11 unique scenarios for each training stage:

1. **Physical Fitness Assessment** - Cardiovascular and strength tests
2. **Mental Health Screening** - Psychological resilience assessment
3. **Technical Knowledge Test** - Space systems and procedures
4. **Emergency Procedures Training** - Crisis response protocols
5. **Space Suit Operations** - EVA suit handling and maintenance
6. **Zero Gravity Simulation** - Weightlessness adaptation
7. **Mission Planning** - Flight planning and navigation
8. **Communication Protocols** - Ground control communication
9. **Equipment Familiarization** - Spacecraft systems training
10. **Mission Simulation** - Full mission rehearsal
11. **Final Certification** - Complete readiness assessment

## Message Flow

1. **Receive Request**: Listens for simulation requests on `simulation_requests` channel
2. **Process Simulation**: Runs realistic simulation with configurable delay
3. **Generate Result**: Creates success/failure result based on success rate
4. **Publish Response**: Sends result back on `simulation_responses` channel

## Testing

```bash
# Run all tests
uv run pytest

# Run specific test categories
uv run pytest -m unit          # Unit tests only
uv run pytest -m integration   # Integration tests only
uv run pytest -m redis         # Tests requiring Redis

# Run with coverage
uv run pytest --cov --cov-report=html
```

## Docker

```bash
# Build image
docker build -t apollo11-simulator .

# Run container
docker run apollo11-simulator
```

## Monitoring

The simulator logs all simulation activities:

- Simulation requests received
- Processing delays
- Simulation results
- Error conditions

Check logs for debugging and monitoring:

```bash
# Docker logs
docker logs apollo11-simulator

# Kubernetes logs
kubectl logs -n apollo11 deployment/simulator -f
```
