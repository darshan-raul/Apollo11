package main

import (
	"log"
	"os"

	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/fiber/v2/middleware/logger"
	"github.com/joho/godotenv"
)

type PaymentRequest struct {
	UserID string  `json:"user_id"`
	Amount float64 `json:"amount"`
}

func main() {
	if err := godotenv.Load(); err != nil {
		log.Println("No .env file found")
	}

	app := fiber.New()
	app.Use(logger.New())

	app.Get("/health/live", func(c *fiber.Ctx) error {
		return c.JSON(fiber.Map{
			"status": "alive",
		})
	})

	app.Get("/health/ready", func(c *fiber.Ctx) error {
		return c.JSON(fiber.Map{
			"status": "ready",
		})
	})

	app.Post("/pay", func(c *fiber.Ctx) error {
		var req PaymentRequest
		if err := c.BodyParser(&req); err != nil {
			return c.Status(400).JSON(fiber.Map{"error": "Invalid request"})
		}

		log.Printf("Processing payment for user %s amount %.2f", req.UserID, req.Amount)

		// Simulating call to Notification Service would happen here
		// For now, just return success

		return c.JSON(fiber.Map{
			"status":         "success",
			"transaction_id": "tx_123456",
		})
	})

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	log.Fatal(app.Listen(":" + port))
}
