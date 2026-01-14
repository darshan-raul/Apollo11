package main

import (
	"log"

	"github.com/joho/godotenv"
)

func main() {
	if err := godotenv.Load(); err != nil {
		log.Println("No .env file found")
	}

	log.Println("Report Generator Job started")
	generateReport()
}

func generateReport() {
	log.Println("Generating daily report...")
	// Logic to connect to DB and generate report
	// ...
	log.Println("Report generated successfully.")
}
