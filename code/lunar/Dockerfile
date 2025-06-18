FROM golang:1.21-alpine AS builder
WORKDIR /app
COPY . .
RUN go mod tidy && go build -o lunar-module

FROM alpine:latest
WORKDIR /app
COPY --from=builder /app/lunar-module .
CMD ["./lunar-module"]
