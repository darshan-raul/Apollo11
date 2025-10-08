# Apollo 11 Shared Module

Common schemas, database models, and utilities shared across the Apollo 11 Astronaut Onboarding System.

## Features

- Pydantic data models and schemas
- SQLAlchemy database models
- Database connection utilities
- Common data structures and enums
- Shared configuration and constants

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

## Module Structure

### Schemas (`schemas.py`)

Pydantic models for data validation and serialization:

- **User Models**: `User`, `UserCreate`, `UserLogin`
- **Stage Models**: `Stage`, `StageProgress`, `StageStatus`
- **Simulation Models**: `SimulationRequest`, `SimulationResponse`
- **Statistics Models**: `UserStats`, `SystemStats`
- **Redis Message Models**: `RedisMessage`, `SimulationMessage`

### Database (`database.py`)

SQLAlchemy models and database utilities:

- **User Model**: User accounts and profiles
- **Stage Model**: Training stage definitions
- **StageProgress Model**: User progress tracking
- **SimulationLog Model**: Simulation history
- **Database Connection**: Connection management and session handling

### Constants

- **STAGES**: 11 predefined astronaut training stages
- **StageStatus**: Enum for stage status values
- **SimulationResult**: Enum for simulation outcomes

## Usage

### Importing Schemas

```python
from apollo11.shared.schemas import User, UserCreate, StageProgress
from apollo11.shared.database import get_db, User as DBUser
```

### Database Operations

```python
from apollo11.shared.database import get_db, init_database

# Initialize database
init_database()

# Get database session
db = next(get_db())
```

### Data Validation

```python
from apollo11.shared.schemas import UserCreate

# Validate user data
user_data = UserCreate(
    username="astronaut1",
    email="astronaut1@nasa.gov",
    full_name="John Astronaut",
    password="secure_password"
)
```

## Environment Variables

```env
DATABASE_URL=postgres://apollo11:apollo11@postgres:5432/apollo11?sslmode=disable
```

## Database Schema

### Users Table
- `id`: Primary key
- `username`: Unique username
- `email`: Unique email address
- `full_name`: User's full name
- `password_hash`: Hashed password
- `is_active`: Account status
- `created_at`: Account creation timestamp

### Stages Table
- `id`: Primary key
- `name`: Stage name
- `description`: Stage description
- `max_attempts`: Maximum allowed attempts
- `created_at`: Stage creation timestamp

### Stage Progress Table
- `id`: Primary key
- `user_id`: Foreign key to users
- `stage_id`: Foreign key to stages
- `status`: Current stage status
- `attempts`: Number of attempts
- `completed_at`: Completion timestamp
- `simulation_result`: Last simulation result
- `simulation_data`: JSON simulation data

### Simulation Logs Table
- `id`: Primary key
- `user_id`: Foreign key to users
- `stage_id`: Foreign key to stages
- `attempt_number`: Attempt number
- `result`: Simulation result
- `message`: Result message
- `simulation_data`: JSON simulation data
- `timestamp`: Simulation timestamp

## Testing

```bash
# Run all tests
uv run pytest

# Run specific test categories
uv run pytest -m unit          # Unit tests only
uv run pytest -m integration   # Integration tests only
uv run pytest -m database      # Database tests only

# Run with coverage
uv run pytest --cov --cov-report=html
```

## Integration

This shared module is used by:

- **Frontend Service**: User authentication and data validation
- **Core API Service**: Database operations and business logic
- **Admin Dashboard**: Data models and database queries
- **Simulator Service**: Message schemas and data structures

## Contributing

When adding new schemas or models:

1. Add Pydantic models to `schemas.py`
2. Add SQLAlchemy models to `database.py`
3. Update the `__init__.py` exports
4. Add comprehensive tests
5. Update documentation

## Version Compatibility

This module is designed to work with:
- Python 3.11+
- Pydantic 2.x
- SQLAlchemy 2.x
- PostgreSQL 12+
