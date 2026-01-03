# Quiz Service

Golang Microservice for Quiz Logic.

## Responsibilities
- Serve random questions
- Grade answers
- Store attempts

## Run
```bash
docker build -t quiz-service .
docker run -p 8080:8080 quiz-service
```
