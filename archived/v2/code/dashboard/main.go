package main

import (
	"bytes"
	"encoding/json"
	"io"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/template/html/v2"
)

type Telemetry struct {
	Timestamp string  `json:"timestamp"`
	Position  float64 `json:"position"`
	Speed     float64 `json:"speed"`
	Status    string  `json:"status"`
	Received  string  `json:"received"`
}

type Event struct {
	ID   string    `json:"id"`
	Name string    `json:"name"`
	Time time.Time `json:"time"`
}

type Command struct {
	Command string `json:"command"`
	Status  string `json:"status"`
}

type DashboardData struct {
	Telemetry []Telemetry
	Events    []Event
	Commands  []Command
}

func fetchTelemetry() []Telemetry {
	url := os.Getenv("TELEMETRY_URL")
	if url == "" {
		url = "http://telemetry-app:8000/data"
	}

	resp, err := http.Get(url)
	if err != nil {
		log.Printf("Error fetching telemetry: %v", err)
		return []Telemetry{}
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)
	var result struct{ Data [][]interface{} }
	json.Unmarshal(body, &result)

	var out []Telemetry
	for _, row := range result.Data {
		if len(row) >= 5 {
			out = append(out, Telemetry{
				Timestamp: row[0].(string),
				Position:  row[1].(float64),
				Speed:     row[2].(float64),
				Status:    row[3].(string),
				Received:  row[4].(string),
			})
		}
	}
	return out
}

func fetchEvents() []Event {
	url := os.Getenv("TIMELINE_URL")
	if url == "" {
		url = "http://timeline-app:8080/data"
	}

	resp, err := http.Get(url)
	if err != nil {
		log.Printf("Error fetching events: %v", err)
		return []Event{}
	}
	defer resp.Body.Close()

	var events []Event
	json.NewDecoder(resp.Body).Decode(&events)
	return events
}

func sendCommand(command string) string {
	url := os.Getenv("COMMAND_DISPATCHER_URL")
	if url == "" {
		url = "http://command-dispatcher:8000/command"
	}

	payload := map[string]string{"command": command}
	jsonData, _ := json.Marshal(payload)

	resp, err := http.Post(url, "application/json", bytes.NewBuffer(jsonData))
	if err != nil {
		log.Printf("Error sending command: %v", err)
		return "Failed to send command"
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)
	return string(body)
}

func addEvent(name, timeStr string) error {
	url := os.Getenv("TIMELINE_URL")
	if url == "" {
		url = "http://timeline-app:8080/input"
	}

	eventTime, err := time.Parse("2006-01-02T15:04", timeStr)
	if err != nil {
		return err
	}

	payload := Event{
		Name: name,
		Time: eventTime,
	}
	jsonData, _ := json.Marshal(payload)

	resp, err := http.Post(url, "application/json", bytes.NewBuffer(jsonData))
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	return nil
}

func main() {
	// Initialize template engine with correct path
	engine := html.New("./templates", ".html")

	// Add template reloading for development
	engine.Reload(true)
	engine.Debug(true)

	// Add custom functions
	engine.AddFunc("now", func() time.Time {
		return time.Now()
	})

	app := fiber.New(fiber.Config{
		Views: engine,
	})

	// Serve static files
	app.Static("/static", "./static")

	// Main dashboard page
	app.Get("/", func(c *fiber.Ctx) error {
		data := DashboardData{
			Telemetry: fetchTelemetry(),
			Events:    fetchEvents(),
		}
		return c.Render("index", data)
	})

	// HTMX endpoints for real-time updates
	app.Get("/telemetry", func(c *fiber.Ctx) error {
		telemetry := fetchTelemetry()
		return c.Render("telemetry", fiber.Map{"Telemetry": telemetry})
	})

	app.Get("/events", func(c *fiber.Ctx) error {
		events := fetchEvents()
		return c.Render("events", fiber.Map{"Events": events})
	})

	// Command endpoints
	app.Post("/command", func(c *fiber.Ctx) error {
		var cmd struct {
			Command string `json:"command"`
		}
		if err := c.BodyParser(&cmd); err != nil {
			return c.Status(400).JSON(fiber.Map{"error": err.Error()})
		}

		status := sendCommand(cmd.Command)
		return c.JSON(fiber.Map{"status": status})
	})

	// Event endpoints
	app.Post("/event", func(c *fiber.Ctx) error {
		var event struct {
			Name string `json:"name"`
			Time string `json:"time"`
		}
		if err := c.BodyParser(&event); err != nil {
			return c.Status(400).JSON(fiber.Map{"error": err.Error()})
		}

		err := addEvent(event.Name, event.Time)
		if err != nil {
			return c.Status(500).JSON(fiber.Map{"error": err.Error()})
		}

		return c.JSON(fiber.Map{"status": "Event added successfully"})
	})

	log.Fatal(app.Listen(":8080"))
}
