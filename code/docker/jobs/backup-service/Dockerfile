FROM golang:1.22 AS builder

WORKDIR /app

COPY go.mod ./
COPY . .
RUN go mod tidy

RUN CGO_ENABLED=0 GOOS=linux go build -o backup-service cmd/main.go

FROM scratch

COPY --from=builder /app/backup-service /backup-service

CMD ["/backup-service"]
