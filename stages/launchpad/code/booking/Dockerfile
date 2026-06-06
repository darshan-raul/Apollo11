FROM golang:1.22-alpine AS builder

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY . .

RUN CGO_ENABLED=0 GOOS=linux go build -o /booking-service

FROM alpine:3.19

RUN apk --no-cache add ca-certificates

WORKDIR /app

COPY --from=builder /booking-service /app/booking-service

ENV DATABASE_URL=postgresql://postgres:postgres@booking-db:5432/booking

EXPOSE 8082

CMD ["/app/booking-service"]