FROM golang:1.22-alpine AS builder

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY . .

RUN CGO_ENABLED=0 GOOS=linux go build -o /flight-service

FROM alpine:3.19

RUN apk --no-cache add ca-certificates

WORKDIR /app

COPY --from=builder /flight-service /app/flight-service

ENV DATABASE_URL=postgresql://postgres:postgres@flight-db:5432/flight

EXPOSE 8081

CMD ["/app/flight-service"]