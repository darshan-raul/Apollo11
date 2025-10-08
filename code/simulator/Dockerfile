FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install uv
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

#Copy application code
COPY . .

# Install dependencies using uv
RUN uv sync --frozen --no-dev

#

# Run the application using uv
CMD ["uv", "run", "python", "main.py"]
