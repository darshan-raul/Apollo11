# Apollo 11 - Kubernetes Learning Platform

A progressive learning platform where the platform itself is the curriculum.

## Architecture
- **Portal**: React SPA
- **Core API**: FastAPI
- **Quiz Service**: Golang
- **Admin**: Streamlit
- **DB**: PostgreSQL
- **Auth**: Keycloak

## Deployment

### Local (Docker Compose)
```bash
docker-compose up --build
```

### Kubernetes
```bash
kubectl apply -f k8s/
```
