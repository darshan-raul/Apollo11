package main

import (
	"bytes"
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"math/rand"
	"net/http"
	"os"
	"time"

	"github.com/gofiber/fiber/v2"
	_ "github.com/lib/pq"
)

type Telemetry struct {
	Timestamp time.Time `json:"timestamp"`
	Position  float64   `json:"position"`
	Speed     float64   `json:"speed"`
	Status    string    `json:"status"`
}

type Command struct {
	ID          int             `json:"id"`
	Timestamp   time.Time       `json:"timestamp"`
	CommandType string          `json:"command_type"`
	Parameters  json.RawMessage `json:"parameters"`
	Status      string          `json:"status"`
}

var db *sql.DB

func initDB() {
	dbHost := os.Getenv("DB_HOST")
	dbPort := os.Getenv("DB_PORT")
	dbUser := os.Getenv("DB_USER")
	dbPassword := os.Getenv("DB_PASSWORD")
	dbName := os.Getenv("DB_NAME")

	// Default values if environment variables are not set
	if dbHost == "" {
		dbHost = "localhost"
	}
	if dbPort == "" {
		dbPort = "5432"
	}
	if dbUser == "" {
		dbUser = "postgres"
	}
	if dbPassword == "" {
		dbPassword = "postgres"
	}
	if dbName == "" {
		dbName = "lunar"
	}

	connStr := fmt.Sprintf("postgres://%s:%s@%s:%s/%s?sslmode=disable",
		dbUser, dbPassword, dbHost, dbPort, dbName)

	var err error
	db, err = sql.Open("postgres", connStr)
	if err != nil {
		log.Fatal(err)
	}

	err = db.Ping()
	if err != nil {
		log.Fatal(err)
	}
}

func generateTelemetry() Telemetry {
	return Telemetry{
		Timestamp: time.Now(),
		Position:  rand.Float64() * 360,     // degrees around the moon
		Speed:     1.6 + rand.Float64()*0.1, // km/s
		Status:    "OK",
	}
}

func saveTelemetry(t Telemetry) error {
	_, err := db.Exec(
		"INSERT INTO telemetry (timestamp, position, speed, status) VALUES ($1, $2, $3, $4)",
		t.Timestamp, t.Position, t.Speed, t.Status,
	)
	return err
}

func sendTelemetry(t Telemetry) {
	url := os.Getenv("TELEMETRY_URL")
	if url == "" {
		url = "http://telemetry:8000/input"
	}
	data, _ := json.Marshal(t)
	http.Post(url, "application/json", bytes.NewBuffer(data))
}

func getLatestCommand() (*Command, error) {
	var cmd Command
	err := db.QueryRow(
		"SELECT id, timestamp, command_type, parameters, status FROM commands WHERE status = 'PENDING' ORDER BY timestamp DESC LIMIT 1",
	).Scan(&cmd.ID, &cmd.Timestamp, &cmd.CommandType, &cmd.Parameters, &cmd.Status)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &cmd, nil
}

func updateCommandStatus(id int, status string) error {
	_, err := db.Exec("UPDATE commands SET status = $1 WHERE id = $2", status, id)
	return err
}

func main() {
	initDB()
	defer db.Close()

	app := fiber.New()

	app.Get("/health", func(c *fiber.Ctx) error {
		return c.SendString("OK")
	})

	app.Get("/command", func(c *fiber.Ctx) error {
		cmd, err := getLatestCommand()
		if err != nil {
			return c.Status(500).JSON(fiber.Map{"error": err.Error()})
		}
		if cmd == nil {
			return c.Status(404).JSON(fiber.Map{"message": "No pending commands"})
		}

		// Update command status to PROCESSING
		err = updateCommandStatus(cmd.ID, "PROCESSING")
		if err != nil {
			return c.Status(500).JSON(fiber.Map{"error": err.Error()})
		}

		return c.JSON(cmd)
	})

	go func() {
		for {
			t := generateTelemetry()
			err := saveTelemetry(t)
			if err != nil {
				log.Printf("Error saving telemetry: %v", err)
			}
			//sendTelemetry(t)
			time.Sleep(30 * time.Second)
		}
	}()

	log.Fatal(app.Listen(":8080"))
}
