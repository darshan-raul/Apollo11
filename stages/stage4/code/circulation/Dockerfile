# Build stage
FROM golang:1.21-alpine AS builder

WORKDIR /src

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o /bin/circulation .

# Runtime stage
FROM scratch

COPY --from=builder /bin/circulation /bin/circulation

EXPOSE 8082

ENTRYPOINT ["/bin/circulation"]