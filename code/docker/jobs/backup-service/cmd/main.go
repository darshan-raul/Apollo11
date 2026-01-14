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

	log.Println("Backup Service Job started")

	ticker := time.NewTicker(12 * time.Hour)
	defer ticker.Stop()

	for {
		select {
		case <-ticker.C:
			performBackup()
		}
	}
}

func performBackup() {
	log.Println("Starting database backup...")
	// Logic to shell out to pg_dump or similar
	// ...
	log.Println("Backup completed successfully.")
}
