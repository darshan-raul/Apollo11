# Circulation Service

Go/Gin service for managing book loans, returns, and reservations. Uses PostgreSQL.

## Ports
- 8082 (HTTP)

## Environment Variables
- `DATABASE_URL`: PostgreSQL connection string (default: postgresql://postgres:***@localhost:5434/circulation)
- `PORT`: Override default port 8082

## Endpoints
- GET /health - Health check
- POST /loans - Borrow a book
- POST /loans/:id/return - Return a book
- GET /loans - List user's loans
- POST /reservations - Reserve a book
- GET /reservations - List user's reservations
- DELETE /reservations/:id - Cancel reservation

## Database
- PostgreSQL on port 5434, database: circulation
- Tables: patrons, loans, reservations

## Build & Run
```bash
go run main.go
# or
docker build -t circulation . && docker run -p 8082:8082 circulation
```