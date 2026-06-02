# Catalog Service

Go/Gin service for managing library books and authors. Uses PostgreSQL + Redis.

## Ports
- 8081 (HTTP)

## Environment Variables
- `DATABASE_URL`: PostgreSQL connection string (default: postgresql://postgres:***@localhost:5433/catalog)
- `REDIS_URL`: Redis connection string (default: redis://localhost:6379)
- `PORT`: Override default port 8081

## Endpoints
- GET /health - Health check
- GET /books - List books (with search, genre, author filters)
- GET /books/:id - Get book by ID
- POST /books - Create book (admin)
- GET /authors - List authors
- GET /authors/:id - Get author by ID
- POST /authors - Create author (admin)

## Database
- PostgreSQL on port 5433, database: catalog
- Tables: authors, books

## Cache (Redis port 6379)
- Key patterns: catalog:book:{id}, catalog:author:{id}, catalog:search:{hash}

## Build & Run
```bash
go run main.go
# or
docker build -t catalog . && docker run -p 8081:8081 catalog
```