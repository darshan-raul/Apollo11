# Frontend Service

Serves static HTML for the Apollo11 library management system. Built with Go/Gin.

## Ports
- 3000 (HTTP)

## Environment
- None required for stub

## Build & Run
```bash
go run main.go
# or
docker build -t frontend . && docker run -p 3000:3000 frontend
```

## Endpoints
- GET / - HTML page
- GET /health - Health check