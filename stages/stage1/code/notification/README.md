# Notification Service

Go/Gin service for managing email/SMS notifications via Redis queue.

## Ports
- 8083 (HTTP)

## Environment Variables
- `REDIS_URL`: Redis connection string (default: redis://localhost:6380)
- `PORT`: Override default port 8083

## Endpoints
- GET /health - Health check
- POST /notifications - Enqueue notification (admin/system)
- GET /notifications - Get queue depth (admin)

## Redis (port 6380)
- Queue key: notifications:queue (LIST)
- Notification format: JSON with id, type, recipient, subject, body, created_at

## Build & Run
```bash
go run main.go
# or
docker build -t notification . && docker run -p 8083:8083 notification
```