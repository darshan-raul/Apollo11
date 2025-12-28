FROM golang:1.22 AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o core-api .

FROM alpine:latest
WORKDIR /root/
COPY --from=builder /app/core-api .
EXPOSE 8080
CMD ["./core-api"]
