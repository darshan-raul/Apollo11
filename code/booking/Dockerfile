FROM golang:1.23-alpine AS builder

WORKDIR /build

COPY go.mod go.sum ./
RUN go mod download

COPY . .

ENV CGO_ENABLED=0 GOOS=linux
RUN go build -ldflags="-s -w" -o booking .

FROM scratch

COPY --from=builder ["/build/booking", "/"]

ENTRYPOINT ["/booking"]