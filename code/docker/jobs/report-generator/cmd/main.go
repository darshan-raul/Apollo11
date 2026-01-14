package main

import (
	"log"
	"time"

	"github.com/joho/godotenv"
)

func main() {
	if err := godotenv.Load(); err != nil {
		log.Println("No .env file found")
	}

	log.Println("Report Generator Job started")

	// Simulate a job that runs periodically
	ticker := time.NewTicker(1 * time.Minute)
	defer ticker.Stop()

	for {
		select {
		case <-ticker.C:
			generateReport()
		}
	}
}

func generateReport() {
	log.Println("Generating daily report...")
	// Logic to connect to DB and generate report
	// ...
	log.Println("Report generated successfully.")

	// Simulate notifying via Payment API or Notification Service if needed
}
