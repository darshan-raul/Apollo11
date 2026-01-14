FROM golang:1.22 AS builder

WORKDIR /app

COPY go.mod ./
COPY . .
RUN go mod tidy

RUN CGO_ENABLED=0 GOOS=linux go build -o payment-api cmd/server/main.go

FROM scratch

COPY --from=builder /app/payment-api /payment-api

EXPOSE 8080

CMD ["/payment-api"]
