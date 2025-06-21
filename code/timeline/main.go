package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"time"

	"github.com/gofiber/fiber/v2"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

type Event struct {
	ID   primitive.ObjectID `json:"id" bson:"_id,omitempty"`
	Name string             `json:"name" bson:"name"`
	Time time.Time          `json:"time" bson:"time"`
}

func main() {
	// MongoDB connection with authentication
	mongoURI := os.Getenv("MONGODB_URI")
	if mongoURI == "" {
		// Build connection string with credentials
		username := os.Getenv("MONGO_USERNAME")
		password := os.Getenv("MONGO_PASSWORD")
		host := os.Getenv("MONGO_HOST")
		if host == "" {
			host = "localhost"
		}
		port := os.Getenv("MONGO_PORT")
		if port == "" {
			port = "27017"
		}

		if username != "" && password != "" {
			mongoURI = fmt.Sprintf("mongodb://%s:%s@%s:%s", username, password, host, port)
		} else {
			mongoURI = fmt.Sprintf("mongodb://%s:%s", host, port)
		}
	}

	client, err := mongo.Connect(context.Background(), options.Client().ApplyURI(mongoURI))
	if err != nil {
		log.Fatal(err)
	}
	defer client.Disconnect(context.Background())

	// Ping the database
	err = client.Ping(context.Background(), nil)
	if err != nil {
		log.Fatal(err)
	}

	// Get database and collection
	db := client.Database("timeline")
	collection := db.Collection("events")

	app := fiber.New()

	app.Get("/data", func(c *fiber.Ctx) error {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()

		cursor, err := collection.Find(ctx, bson.M{})
		if err != nil {
			return c.Status(500).JSON(fiber.Map{"error": err.Error()})
		}
		defer cursor.Close(ctx)

		var events []Event
		if err = cursor.All(ctx, &events); err != nil {
			return c.Status(500).JSON(fiber.Map{"error": err.Error()})
		}

		return c.JSON(events)
	})

	app.Post("/input", func(c *fiber.Ctx) error {
		var e Event
		if err := c.BodyParser(&e); err != nil {
			return c.Status(400).JSON(fiber.Map{"error": err.Error()})
		}

		// Set current time if not provided
		if e.Time.IsZero() {
			e.Time = time.Now()
		}

		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()

		result, err := collection.InsertOne(ctx, e)
		if err != nil {
			return c.Status(500).JSON(fiber.Map{"error": err.Error()})
		}

		e.ID = result.InsertedID.(primitive.ObjectID)
		return c.Status(201).JSON(e)
	})

	log.Fatal(app.Listen(":8080"))
}
