FROM golang:1.22 AS builder

WORKDIR /app

COPY go.mod ./
COPY . .
RUN go mod tidy

RUN CGO_ENABLED=0 GOOS=linux go build -o report-generator cmd/main.go

FROM scratch

COPY --from=builder /app/report-generator /report-generator

CMD ["/report-generator"]
