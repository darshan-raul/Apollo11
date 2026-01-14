package main

import (
	"context"
	"encoding/json"
	"log"
	"os"

	"github.com/apollo11/quiz-service/internal/models"
	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/fiber/v2/middleware/cors"
	"github.com/gofiber/fiber/v2/middleware/logger"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

var db *pgxpool.Pool

func main() {
	// Database connection
	dbUrl := os.Getenv("DATABASE_URL")
	if dbUrl == "" {
		dbUrl = "postgres://postgres:postgres@postgres:5432/apollo11"
	}

	config, err := pgxpool.ParseConfig(dbUrl)
	if err != nil {
		log.Fatalf("Unable to parse DB URL: %v", err)
	}

	var connErr error
	db, connErr = pgxpool.NewWithConfig(context.Background(), config)
	if connErr != nil {
		log.Fatalf("Unable to connect to database: %v", connErr)
	}
	defer db.Close()

	app := fiber.New()
	app.Use(logger.New())
	app.Use(cors.New())

	// Routes
	app.Get("/health/live", func(c *fiber.Ctx) error {
		return c.JSON(fiber.Map{"status": "alive"})
	})
	app.Get("/health/ready", func(c *fiber.Ctx) error {
		if db == nil {
			return c.Status(503).JSON(fiber.Map{"status": "not ready", "error": "database connection unavailable"})
		}
		if err := db.Ping(context.Background()); err != nil {
			return c.Status(503).JSON(fiber.Map{"status": "not ready", "error": err.Error()})
		}
		return c.JSON(fiber.Map{"status": "ready"})
	})
	app.Post("/quiz/start", startQuiz)
	app.Post("/quiz/evaluate", evaluateQuiz)
	app.Get("/quiz/results/:user_id", getResults)

	log.Fatal(app.Listen(":8080"))
}

func startQuiz(c *fiber.Ctx) error {
	var req models.StartQuizRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "Invalid request"})
	}

	// Fetch 5 random questions for the stage
	rows, err := db.Query(context.Background(),
		"SELECT id, question, options FROM quiz.quiz_questions WHERE stage_id = $1 ORDER BY RANDOM() LIMIT 5", req.StageID)
	if err != nil {
		return c.Status(500).JSON(fiber.Map{"error": "Database error fetching questions"})
	}
	defer rows.Close()

	var questions []models.QuestionView
	for rows.Next() {
		var q models.QuizQuestion
		// we only select id, question, options
		// options is stored as JSONB in DB, but scanned as string/bytes via pgx?
		// pgx can scan into string or []byte.
		var optionsJSON string
		if err := rows.Scan(&q.ID, &q.Question, &optionsJSON); err != nil {
			return c.Status(500).JSON(fiber.Map{"error": "Error scanning questions"})
		}

		var opts []string
		if err := json.Unmarshal([]byte(optionsJSON), &opts); err != nil {
			// Handle error or skip
			log.Printf("Error unmarshalling options: %v", err)
		}

		questions = append(questions, models.QuestionView{
			ID:       q.ID,
			Question: q.Question,
			Options:  opts,
		})
	}

	return c.JSON(models.StartQuizResponse{
		Questions: questions,
	})
}

func evaluateQuiz(c *fiber.Ctx) error {
	var req models.SubmitQuizRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "Invalid request"})
	}

	// Fetch correct answers for the questions
	// We iterate over answers submitted
	score := 0
	total := 0

	for qID, answer := range req.Answers {
		total++
		var correctAnswer string
		err := db.QueryRow(context.Background(), "SELECT correct_answer FROM quiz.quiz_questions WHERE id = $1", qID).Scan(&correctAnswer)
		if err != nil {
			if err == pgx.ErrNoRows {
				continue
			}
			log.Printf("Error checking answer: %v", err)
			continue
		}

		if answer == correctAnswer {
			score++
		}
	}

	// Pass threshold: 60% ?
	passed := false
	if total > 0 && float64(score)/float64(total) >= 0.6 {
		passed = true
	}

	// Persist attempt
	_, err := db.Exec(context.Background(),
		"INSERT INTO quiz.quiz_attempts (user_id, stage_id, score, passed) VALUES ($1, $2, $3, $4)",
		req.UserID, req.StageID, score, passed)

	if err != nil {
		log.Printf("Error saving attempt: %v", err)
		// We might still return result but log error
	}

	return c.JSON(models.SubmitQuizResponse{
		Score:  score,
		Passed: passed,
	})
}

func getResults(c *fiber.Ctx) error {
	userID := c.Params("user_id")

	rows, err := db.Query(context.Background(),
		"SELECT stage_id, score, passed, attempted_at FROM quiz.quiz_attempts WHERE user_id = $1 ORDER BY attempted_at DESC", userID)
	if err != nil {
		return c.Status(500).JSON(fiber.Map{"error": "Database error"})
	}
	defer rows.Close()

	var results []map[string]interface{}
	for rows.Next() {
		var r models.QuizAttempt
		if err := rows.Scan(&r.StageID, &r.Score, &r.Passed, &r.AttemptedAt); err != nil {
			continue
		}
		results = append(results, map[string]interface{}{
			"stage_id":     r.StageID,
			"score":        r.Score,
			"passed":       r.Passed,
			"attempted_at": r.AttemptedAt,
		})
	}

	return c.JSON(results)
}
