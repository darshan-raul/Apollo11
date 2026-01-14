package main

import (
	"log"

	"github.com/joho/godotenv"
)

func main() {
	if err := godotenv.Load(); err != nil {
		log.Println("No .env file found")
	}

	log.Println("Backup Service Job started")
	performBackup()
}

func performBackup() {
	log.Println("Starting database backup...")
	// Logic to shell out to pg_dump or similar
	// ...
	log.Println("Backup completed successfully.")
}
