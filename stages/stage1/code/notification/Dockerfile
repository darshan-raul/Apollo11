# Build stage
FROM golang:1.21-alpine AS builder

WORKDIR /src

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o /bin/notification .

# Runtime stage
FROM scratch

COPY --from=builder /bin/notification /bin/notification

EXPOSE 8083

ENTRYPOINT ["/bin/notification"]