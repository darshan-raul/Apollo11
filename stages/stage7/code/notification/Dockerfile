FROM golang:1.27.3-alpine3.24 AS builder

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY . .

RUN CGO_ENABLED=0 GOOS=linux go build -o /notification-service

FROM alpine:3.24.2

# Pick up Alpine security fixes published after this image was built.
RUN apk upgrade --no-cache && apk --no-cache add ca-certificates \
    && addgroup -S -g 10001 apollo \
    && adduser -S -D -H -u 10001 -G apollo apollo

WORKDIR /app

COPY --from=builder --chown=10001:10001 /notification-service /app/notification-service

EXPOSE 8084

# Numeric UID so Kubernetes runAsNonRoot can verify it (Stage 8).
USER 10001:10001

CMD ["/app/notification-service"]