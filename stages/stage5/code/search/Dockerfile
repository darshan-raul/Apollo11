FROM golang:1.27.3-alpine3.24 AS builder

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY . .

RUN CGO_ENABLED=0 GOOS=linux go build -o /search-service

FROM alpine:3.24.2

# Pick up Alpine security fixes published after this image was built.
RUN apk upgrade --no-cache && apk --no-cache add ca-certificates

WORKDIR /app

COPY --from=builder /search-service /app/search-service

EXPOSE 8083

CMD ["/app/search-service"]