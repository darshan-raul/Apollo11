# Apollo 11 Frontend Service

FastAPI-based frontend application for the Apollo 11 Astronaut Onboarding System.

## Features

- Modern, responsive web interface with Bootstrap 5
- User registration and authentication
- Stage progression tracking
- Real-time simulation updates
- JWT-based authentication with Redis sessions

## Development Setup

### Prerequisites

- Python 3.11+
- [uv](https://docs.astral.sh/uv/) package manager

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
# Development server with auto-reload
uv run uvicorn main:app --host 0.0.0.0 --port 8000 --reload

# Or using the script
uv run python main.py
```

### Development Commands

```bash
# Install development dependencies
uv sync --dev

# Run tests
uv run pytest

# Run tests with coverage
uv run pytest --cov

# Format code
uv run black .
uv run isort .

# Type checking
uv run mypy .

# Linting
uv run flake8 .
```

## Environment Variables

Create a `.env` file in the frontend directory:

```env
DATABASE_URL=postgres://apollo11:apollo11@postgres:5432/apollo11?sslmode=disable
CORE_API_URL=http://core-api:8080
REDIS_URL=redis://redis:6379
```

## API Endpoints

- `GET /` - Home page
- `GET /login` - Login page
- `GET /register` - Registration page
- `GET /dashboard` - User dashboard
- `GET /stage/{stage_id}` - Individual stage page
- `POST /api/register` - User registration
- `POST /api/login` - User login
- `POST /api/stage/{stage_id}/start` - Start stage simulation
- `GET /api/user/progress` - Get user progress

## Docker

```bash
# Build image
docker build -t apollo11-frontend .

# Run container
docker run -p 8000:8000 apollo11-frontend
```
