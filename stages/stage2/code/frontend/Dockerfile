# Stage 1: Build Go binary
FROM golang:1.21-alpine AS builder

WORKDIR /src

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o /bin/frontend .

# Stage 2: Build nginx static assets
FROM nginx:alpine AS assets

COPY static/* /usr/share/nginx/html/static/

# Stage 3: Runtime — Go binary + nginx
FROM alpine:3.19

RUN apk add --no-cache nginx

# Copy Go binary
COPY --from=builder /bin/frontend /bin/frontend

# Copy nginx config
COPY nginx.conf /etc/nginx/nginx.conf

# Copy static assets
COPY --from=assets /usr/share/nginx/html/static/ /usr/share/nginx/html/static/

EXPOSE 80 3000

# Start nginx in background, then run Go
CMD ["sh", "-c", "nginx -c /etc/nginx/nginx.conf &> /dev/null & sleep 1 && /bin/frontend"]