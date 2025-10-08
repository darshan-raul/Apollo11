# Apollo 11 - UV Package Manager Setup Guide

This guide explains how to use [uv](https://docs.astral.sh/uv/) for fast and reliable Python package management in the Apollo 11 Astronaut Onboarding System.

## Why UV?

- **10-100x faster** than pip for dependency resolution
- **Reproducible builds** with lock files
- **Built-in virtual environment** management
- **Modern tooling** with `pyproject.toml` support
- **Compatible** with existing Python workflows

## Installation

### Install UV

```bash
# Unix/macOS/Linux
curl -LsSf https://astral.sh/uv/install.sh | sh

# Windows (PowerShell)
powershell -c "irm https://astral.sh/uv/install.ps1 | iex"

# Or using pip
pip install uv
```

### Verify Installation

```bash
uv --version
```

## Project Structure

Each Python service now uses `pyproject.toml` instead of `requirements.txt`:

```
code/
├── frontend/
│   ├── pyproject.toml      # FastAPI frontend dependencies
│   ├── uv.lock            # Lock file (generated)
│   └── .venv/             # Virtual environment (generated)
├── simulator/
│   ├── pyproject.toml      # Simulator service dependencies
│   ├── uv.lock            # Lock file (generated)
│   └── .venv/             # Virtual environment (generated)
├── admin-dashboard/
│   ├── pyproject.toml      # Streamlit dashboard dependencies
│   ├── uv.lock            # Lock file (generated)
│   └── .venv/             # Virtual environment (generated)
└── shared/
    ├── pyproject.toml      # Shared module dependencies
    ├── uv.lock            # Lock file (generated)
    └── .venv/             # Virtual environment (generated)
```

## Quick Start

### 1. Set Up All Services

```bash
# From the project root
./scripts/deploy.sh dev-setup
```

This will:
- Install dependencies for all Python services
- Generate lock files for reproducible builds
- Set up virtual environments

### 2. Individual Service Setup

```bash
# Navigate to a service
cd frontend

# Install dependencies
uv sync

# Install with development dependencies
uv sync --dev

# Activate virtual environment (optional)
source .venv/bin/activate  # Unix/macOS
# or
.venv\Scripts\activate     # Windows
```

### 3. Run Services

```bash
# Frontend
cd frontend
uv run uvicorn main:app --host 0.0.0.0 --port 8000 --reload

# Simulator
cd simulator
uv run python main.py

# Admin Dashboard
cd admin-dashboard
uv run streamlit run main.py --server.port=8501 --server.address=0.0.0.0
```

## Common Commands

### Dependency Management

```bash
# Install dependencies
uv sync

# Install with dev dependencies
uv sync --dev

# Add a new dependency
uv add requests

# Add a dev dependency
uv add --dev pytest

# Remove a dependency
uv remove requests

# Update dependencies
uv lock --upgrade
```

### Virtual Environment

```bash
# Create virtual environment
uv venv

# Activate virtual environment
source .venv/bin/activate  # Unix/macOS
.venv\Scripts\activate     # Windows

# Deactivate
deactivate
```

### Running Commands

```bash
# Run Python script
uv run python script.py

# Run with specific Python version
uv run --python 3.11 python script.py

# Run installed package
uv run pytest
uv run black .
uv run mypy .
```

### Lock Files

```bash
# Generate lock file
uv lock

# Update lock file
uv lock --upgrade

# Sync from lock file
uv sync --frozen
```

## Development Workflow

### 1. Initial Setup

```bash
# Clone repository
git clone <repository-url>
cd apollo11/code

# Set up all services
./scripts/deploy.sh dev-setup
```

### 2. Daily Development

```bash
# Navigate to service
cd frontend

# Install any new dependencies
uv sync

# Run tests
uv run pytest

# Format code
uv run black .
uv run isort .

# Type checking
uv run mypy .

# Run the service
uv run uvicorn main:app --reload
```

### 3. Adding Dependencies

```bash
# Add runtime dependency
uv add fastapi

# Add development dependency
uv add --dev pytest

# Add with specific version
uv add "fastapi>=0.100.0"

# Add from git
uv add git+https://github.com/user/repo.git
```

### 4. Updating Dependencies

```bash
# Update all dependencies
uv lock --upgrade

# Update specific dependency
uv lock --upgrade-package fastapi

# Sync with updated lock file
uv sync
```

## Docker Integration

The Dockerfiles have been updated to use uv:

```dockerfile
# Install uv
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.cargo/bin:$PATH"

# Copy pyproject.toml and lock file
COPY pyproject.toml ./
COPY uv.lock* ./

# Install dependencies
RUN uv sync --frozen --no-dev

# Run application
CMD ["uv", "run", "python", "main.py"]
```

## Benefits Over pip/requirements.txt

### Speed
- **10-100x faster** dependency resolution
- **Parallel downloads** and installation
- **Efficient caching** of packages

### Reliability
- **Lock files** ensure reproducible builds
- **Dependency resolution** handles conflicts better
- **Virtual environment** management built-in

### Developer Experience
- **Single tool** for all Python package management
- **Modern configuration** with pyproject.toml
- **Better error messages** and debugging

## Migration from requirements.txt

The project has been migrated from `requirements.txt` to `pyproject.toml`:

### Before (requirements.txt)
```txt
fastapi==0.104.1
uvicorn[standard]==0.24.0
pydantic==2.5.0
```

### After (pyproject.toml)
```toml
[project]
dependencies = [
    "fastapi>=0.104.1",
    "uvicorn[standard]>=0.24.0",
    "pydantic>=2.5.0",
]

[project.optional-dependencies]
dev = [
    "pytest>=7.4.0",
    "black>=23.0.0",
]
```

## Troubleshooting

### Common Issues

1. **UV not found**
   ```bash
   # Reinstall uv
   curl -LsSf https://astral.sh/uv/install.sh | sh
   source ~/.bashrc  # or restart terminal
   ```

2. **Lock file conflicts**
   ```bash
   # Regenerate lock file
   rm uv.lock
   uv lock
   ```

3. **Virtual environment issues**
   ```bash
   # Remove and recreate
   rm -rf .venv
   uv sync
   ```

4. **Dependency conflicts**
   ```bash
   # Check for conflicts
   uv tree
   
   # Resolve conflicts
   uv lock --upgrade
   ```

### Performance Tips

1. **Use lock files** for reproducible builds
2. **Cache dependencies** in CI/CD
3. **Use --frozen** in production
4. **Parallel installation** with multiple cores

## CI/CD Integration

### GitHub Actions Example

```yaml
- name: Install uv
  uses: astral-sh/setup-uv@v1
  with:
    version: "latest"

- name: Install dependencies
  run: uv sync --frozen

- name: Run tests
  run: uv run pytest

- name: Build Docker image
  run: docker build -t apollo11-frontend ./frontend
```

### Docker Multi-stage Build

```dockerfile
# Build stage
FROM python:3.11-slim as builder
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev

# Runtime stage
FROM python:3.11-slim
COPY --from=builder /app/.venv /app/.venv
COPY . .
CMD ["/app/.venv/bin/python", "main.py"]
```

## Best Practices

1. **Always use lock files** for reproducible builds
2. **Separate dev dependencies** from runtime dependencies
3. **Use version constraints** in pyproject.toml
4. **Keep lock files** in version control
5. **Use --frozen** in production environments
6. **Regular dependency updates** with `uv lock --upgrade`

## Resources

- [UV Documentation](https://docs.astral.sh/uv/)
- [UV GitHub Repository](https://github.com/astral-sh/uv)
- [PyProject.toml Specification](https://packaging.python.org/en/latest/specifications/pyproject-toml/)
- [Python Packaging User Guide](https://packaging.python.org/)
