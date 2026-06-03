# Fines Service

Go/Gin service for managing library fines. Uses SQLite.

## Ports
- 8084 (HTTP)

## Environment Variables
- `DATABASE_PATH`: Path to SQLite database (default: /data/fines.db)
- `PORT`: Override default port 8084

## Endpoints
- GET /health - Health check
- GET /fines - Get current user's fines
- POST /fines/:id/pay - Mark fine as paid

## Database
- SQLite at /data/fines.db
- Tables: fines (id, patron_id, loan_id, amount, reason, paid, created_at, paid_at)

## Build & Run
```bash
go run main.go
# or
docker build -t fines . && docker run -p 8084:8084 fines
```