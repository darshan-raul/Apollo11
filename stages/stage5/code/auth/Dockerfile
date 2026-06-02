# Build stage
FROM python:3.11-slim AS builder

WORKDIR /src

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# Runtime stage
FROM python:3.11-slim

WORKDIR /src

COPY --from=builder /src/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY --from=builder /src/ .

EXPOSE 8080

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]