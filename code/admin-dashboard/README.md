# Apollo 11 Admin Dashboard

Streamlit-based admin dashboard for monitoring and analytics of the Apollo 11 Astronaut Onboarding System.

## Features

- Real-time system monitoring and analytics
- User statistics and progress tracking
- Stage performance metrics
- System health monitoring
- Interactive charts and visualizations
- Historical data analysis

## Development Setup

### Prerequisites

- Python 3.11+
- [uv](https://docs.astral.sh/uv/) package manager
- PostgreSQL database
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
# Run the Streamlit app
uv run streamlit run main.py --server.port 8501 --server.address 0.0.0.0

# Or using the script
uv run apollo11-admin-dashboard
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

Create a `.env` file in the admin-dashboard directory:

```env
DATABASE_URL=postgres://apollo11:apollo11@postgres:5432/apollo11?sslmode=disable
REDIS_URL=redis://redis:6379
CORE_API_URL=http://core-api:8080
```

## Dashboard Features

### Overview Tab
- System-wide statistics
- Key performance metrics
- Daily activity charts
- Stage completion rates

### Users Tab
- User management and statistics
- Individual user progress tracking
- Completion rate analysis
- User activity monitoring

### Stages Tab
- Stage performance analytics
- Completion rate by stage
- Attempt vs completion analysis
- Stage difficulty assessment

### Analytics Tab
- Advanced analytics and trends
- Simulation result analysis
- Hourly activity patterns
- Historical performance data

## Configuration

### Database Connection
- `DATABASE_URL`: PostgreSQL connection string
- Automatic connection pooling and caching
- Health checks and error handling

### Redis Integration
- `REDIS_URL`: Redis connection for real-time data
- System status monitoring
- Cache management

### Core API Integration
- `CORE_API_URL`: Core API endpoint for health checks
- Service status monitoring
- API connectivity verification

## Customization

### Adding New Metrics
1. Create new database queries in the appropriate functions
2. Add visualization components using Plotly
3. Update the dashboard layout in the main function

### Styling
- Custom CSS in the main.py file
- Bootstrap-based responsive design
- Color-coded metrics and alerts

### Data Refresh
- Automatic data refresh every 30 seconds
- Manual refresh button in sidebar
- Cached data for performance

## Testing

```bash
# Run all tests
uv run pytest

# Run specific test categories
uv run pytest -m unit          # Unit tests only
uv run pytest -m integration   # Integration tests only
uv run pytest -m streamlit     # Streamlit-specific tests

# Run with coverage
uv run pytest --cov --cov-report=html
```

## Docker

```bash
# Build image
docker build -t apollo11-admin-dashboard .

# Run container
docker run -p 8501:8501 apollo11-admin-dashboard
```

## Performance Optimization

### Caching
- Streamlit caching for database queries
- Redis caching for frequently accessed data
- Connection pooling for database operations

### Data Loading
- Lazy loading of large datasets
- Pagination for user tables
- Optimized SQL queries with proper indexing

## Monitoring

The dashboard provides real-time monitoring of:

- Database connectivity
- Redis connectivity
- Core API health
- Service status
- Error rates and performance metrics

## Troubleshooting

### Common Issues

1. **Database Connection Failed**
   - Check DATABASE_URL configuration
   - Verify PostgreSQL service is running
   - Check network connectivity

2. **Redis Connection Failed**
   - Check REDIS_URL configuration
   - Verify Redis service is running
   - Check Redis memory limits

3. **Core API Unavailable**
   - Check CORE_API_URL configuration
   - Verify Core API service is running
   - Check network connectivity

### Logs and Debugging

```bash
# Streamlit logs
uv run streamlit run main.py --logger.level debug

# Docker logs
docker logs apollo11-admin-dashboard

# Kubernetes logs
kubectl logs -n apollo11 deployment/admin-dashboard -f
```
