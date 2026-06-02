# Auth Service

FastAPI-based authentication service for Apollo11 library management.

## Ports
- 8080 (HTTP)

## Environment Variables
- `DATABASE_URL`: PostgreSQL connection string (default: postgresql://postgres:postgres@localhost:5432/auth)
- `JWT_SECRET`: Secret key for JWT signing (required)
- `PORT`: Override default port 8080

## Endpoints
- POST /register - Register new user
- POST /login - Authenticate and get JWT
- GET /me - Get current user info

## Database
- PostgreSQL on port 5432
- Database name: auth
- Table: users (id, email, password_hash, full_name, role, created_at, updated_at)

## Build & Run
```bash
pip install -r requirements.txt
uvicorn main:app --reload
# or
docker build -t auth . && docker run -p 8080:8080 auth
```