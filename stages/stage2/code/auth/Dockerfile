# Build stage
FROM python:3.11-slim AS builder

WORKDIR /src

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# Runtime stage
FROM python:3.11-slim

WORKDIR /src

RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /src/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY --from=builder /src/ .

EXPOSE 8080

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]