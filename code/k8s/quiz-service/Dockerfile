FROM golang:1.22 AS builder

WORKDIR /app

COPY go.mod ./
RUN go mod download

COPY . .

RUN go mod tidy

RUN CGO_ENABLED=0 GOOS=linux go build -o quiz-service cmd/server/main.go

FROM scratch

COPY --from=builder /app/quiz-service /quiz-service

EXPOSE 8080

CMD ["/quiz-service"]
